import Foundation

/// Talks to the **Orchestration** host — `https://api.purse-{env}.com/payment/v2` — for the two
/// 3DS calls the device makes: versioning and challenge-result. Tokenization and BIN lookup keep
/// going to the Vault host through `VaultAPIClient`; same environment enum, two base URLs.
///
/// Kept as its own class and its own session for the same reason `RemoteLogClient` is: a
/// different host, a different contract, and no card data on the wire — versioning carries a form
/// token or a wallet token id, challenge-result carries a transaction id, and neither ever sees a
/// PAN. SPKI pinning is therefore **not** applied here: `SecureFieldsConfig.pinnedPublicKeyHashes`
/// holds the *Vault* server's keys, and pinning this host with them would reject every request.
/// System trust evaluation applies as usual.
final class ThreeDSAPIClient {

    private let baseURL: String
    /// The gateway api key — the same one monitoring uses (`SecureFieldsConfig.apiKey`). The
    /// Orchestration host sits behind Purse's API gateway, which resolves an API client from an
    /// `X-Api-Key` header (or an `api-key` query parameter) on every proxied request. Sent as a
    /// **header**, never in the URL: a URL is written to proxy and access logs (SDK-12426).
    /// Omitted when the host configured none, exactly as the web SDK omits it.
    private let apiKey: String?
    private let session: URLSession
    /// Versioning sits between the pay tap and the authentication, so the whole retry budget
    /// stays under a second of added latency — the same sizing as the web SDK.
    private let maxRetries = 2

    init(baseURL: String, apiKey: String?) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = URLSession(configuration: .pciSecure)
    }

    /// Test-only init.
    init(baseURL: String, apiKey: String?, session: URLSession) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
        self.usesSessionOverride = true
    }

    private(set) var usesSessionOverride = false

    /// `sessionOverride` is honoured only on a development host, exactly as
    /// `VaultAPIClient.make(…)` does it — a release-signed app must never be able to redirect
    /// these calls (SDK-12425).
    static func make(
        baseURL: String,
        apiKey: String?,
        sessionOverride: URLSession?,
        isDebugHost: Bool
    ) -> ThreeDSAPIClient {
        if let sessionOverride {
            if isDebugHost {
                return ThreeDSAPIClient(baseURL: baseURL, apiKey: apiKey, session: sessionOverride)
            }
            NSLog("PurseSecureFields: urlSessionOverride is not allowed in a release-signed app — ignored on the 3DS client")
        }
        return ThreeDSAPIClient(baseURL: baseURL, apiKey: apiKey)
    }

    // MARK: - Versioning

    func versioning(
        _ body: ThreeDSVersioningRequest,
        completion: @escaping (Result<ThreeDSVersioningResponse, SecureFieldsError>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/3ds/versioning"),
              let encoded = try? JSONEncoder().encode(body) else {
            completion(.failure(.invalidResponse))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(VaultAPIClient.sdkVersion, forHTTPHeaderField: "X-Purse-SDK-Version")
        apiKey.map { request.setValue($0, forHTTPHeaderField: RemoteLogClient.apiKeyHeader) }
        request.httpBody = encoded

        perform(request, retries: maxRetries, call: .versioning) { result in
            completion(result.flatMap { data in
                guard let decoded = try? JSONDecoder().decode(ThreeDSVersioningResponse.self, from: data) else {
                    return .failure(.threeDS(.networkError))
                }
                return .success(decoded)
            })
        }
    }

    // MARK: - Challenge result

    /// Called on **every** terminal challenge callback, cancels and errors included: the
    /// server-side state is the same either way. Never retried — the endpoint is rate-limited per
    /// transaction id and always answers `200`.
    func challengeResult(
        threeDSServerTransID: String,
        completion: @escaping (Result<ThreeDSChallengeResultResponse, SecureFieldsError>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/3ds/challenge-result"),
              // The only field the endpoint accepts: any other is a 400.
              let encoded = try? JSONSerialization.data(
                  withJSONObject: ["three_ds_server_trans_id": threeDSServerTransID]
              ) else {
            completion(.failure(.invalidResponse))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(VaultAPIClient.sdkVersion, forHTTPHeaderField: "X-Purse-SDK-Version")
        apiKey.map { request.setValue($0, forHTTPHeaderField: RemoteLogClient.apiKeyHeader) }
        request.httpBody = encoded

        perform(request, retries: 0, call: .challengeResult) { result in
            completion(result.flatMap { data in
                guard let decoded = try? JSONDecoder().decode(ThreeDSChallengeResultResponse.self, from: data) else {
                    return .failure(.threeDS(.networkError))
                }
                return .success(decoded)
            })
        }
    }

    // MARK: - Transport

    private enum Call: String {
        case versioning
        case challengeResult = "challenge-result"
    }

    private func perform(
        _ request: URLRequest,
        retries: Int,
        call: Call,
        completion: @escaping (Result<Data, SecureFieldsError>) -> Void
    ) {
        // `self` held strongly: it is needed for the retry, and a dropped completion would leave
        // the submit latch closed for good.
        session.dataTask(with: request) { data, response, error in
            // Reported as 3DS failures, not as `.networkError` / `.invalidResponse`: by now the
            // card may be tokenized, and the host must be able to tell (AGENTS.md, "The chain").
            if error != nil {
                completion(.failure(.threeDS(.networkError)))
                return
            }
            guard let http = response as? HTTPURLResponse, let data else {
                completion(.failure(.threeDS(.networkError)))
                return
            }
            #if DEBUG
            print("[SecureFields] 3DS \(call.rawValue) \(http.statusCode)")
            #endif

            // 429 is deliberately not retried: the gateway answers it with `Retry-After`, and
            // hammering a rate limit from inside a payment path only makes it worse.
            if (http.statusCode >= 500 || http.statusCode == 408), retries > 0 {
                self.perform(request, retries: retries - 1, call: call, completion: completion)
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                completion(.failure(.threeDS(Self.problem(call, statusCode: http.statusCode, body: data))))
                return
            }
            completion(.success(data))
        }.resume()
    }

    /// Branches on `status` + `type`, never on the `error` text.
    private static func problem(_ call: Call, statusCode: Int, body: Data) -> ThreeDSError {
        let type = (try? JSONDecoder().decode(ThreeDSProblemResponse.self, from: body))?.type
        switch (call, statusCode, type) {
        case (.versioning, 422, "urn:eu.purse:threeds:card-not-versionable"):
            return .cardNotEligible
        case (.versioning, 422, "urn:eu.purse:threeds:not-configured"):
            return .notConfigured
        case (.versioning, _, _):
            return .versioningFailed(statusCode: statusCode, type: type)
        case (.challengeResult, _, _):
            return .challengeResultFailed(statusCode: statusCode, type: type)
        }
    }
}
