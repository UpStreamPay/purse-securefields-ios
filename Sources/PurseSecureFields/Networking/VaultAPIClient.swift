import CryptoKit
import Foundation

final class VaultAPIClient {

    static let sdkVersion = "0.1.0"

    private let baseURL: String
    private let session: URLSession
    private let maxRetries = 3

    // Retained strongly because URLSession only holds a weak reference to its delegate.
    private let pinningDelegate: PinningDelegate?

    /// Production init — creates an ephemeral, cache-free session.
    /// When `pinnedPublicKeyHashes` is non-empty, certificate pinning is enforced.
    init(baseURL: String, pinnedPublicKeyHashes: [String] = []) {
        self.baseURL = baseURL
        if pinnedPublicKeyHashes.isEmpty {
            #if DEBUG
            print("[SecureFields] WARNING: pinnedPublicKeyHashes is empty — SPKI pinning disabled. Set SecureFieldsConfig.pinnedPublicKeyHashes for production deployments.")
            #endif
            self.pinningDelegate = nil
            self.session = URLSession(configuration: .pciSecure)
        } else {
            let delegate = PinningDelegate(hashes: pinnedPublicKeyHashes)
            self.pinningDelegate = delegate
            self.session = URLSession(
                configuration: .pciSecure,
                delegate: delegate,
                delegateQueue: nil
            )
        }
    }

    /// Test-only init — bypasses pinning entirely.
    init(baseURL: String, session: URLSession) {
        self.baseURL = baseURL
        self.pinningDelegate = nil
        self.session = session
    }

    func binLookup(
        tenantId: String,
        firstDigits: String,
        completion: @escaping (Result<BinLookupResult, SecureFieldsError>) -> Void
    ) {
        let encoded = tenantId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tenantId
        let urlString = "\(baseURL)/v1/tenants/\(encoded)/bin-lookup"
        guard let url = URL(string: urlString) else {
            completion(.failure(.invalidResponse))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.sdkVersion, forHTTPHeaderField: "X-Purse-SDK-Version")

        guard let body = try? JSONEncoder().encode(BinLookupPayload(firstDigits: firstDigits)) else {
            completion(.failure(.invalidResponse))
            return
        }
        request.httpBody = body

        session.dataTask(with: request) { data, response, error in
            if let error {
                #if DEBUG
                print("[SecureFields] BIN lookup error: \(error.localizedDescription)")
                #endif
                completion(.failure(.networkError(error)))
                return
            }

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            #if DEBUG
            print("[SecureFields] BIN lookup \(statusCode)")
            #endif

            guard (200..<300).contains(statusCode) else {
                completion(.failure(.apiError(message: "BIN lookup failed", statusCode: statusCode)))
                return
            }

            guard let data else {
                completion(.failure(.invalidResponse))
                return
            }
            // A malformed 2xx body must fail explicitly — never fall back to a default result and
            // report `.success`, or downstream code silently proceeds on corrupt data.
            // Mirrors the decode handling in `perform(request:retries:completion:)`.
            guard let response = try? JSONDecoder().decode(BinLookupResponse.self, from: data) else {
                #if DEBUG
                print("[SecureFields] BIN lookup decode error")
                #endif
                completion(.failure(.invalidResponse))
                return
            }
            completion(.success(response.toBinLookupResult()))
        }.resume()
    }

    func tokenize(
        tenantId: String,
        payload: TokenizationPayload,
        completion: @escaping (Result<TokenizationResponse, SecureFieldsError>) -> Void
    ) {
        let encoded = tenantId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tenantId
        let urlString = "\(baseURL)/v1/tenants/\(encoded)/forms/secure-fields"
        guard let url = URL(string: urlString) else {
            completion(.failure(.invalidResponse))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.sdkVersion, forHTTPHeaderField: "X-Purse-SDK-Version")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")

        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            completion(.failure(.networkError(error)))
            return
        }

        perform(request: request, retries: maxRetries, completion: completion)
    }

    private func perform(
        request: URLRequest,
        retries: Int,
        completion: @escaping (Result<TokenizationResponse, SecureFieldsError>) -> Void
    ) {
        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            if let error {
                // Transport errors are not retried — the request may have been received by the server.
                // Retrying would risk creating duplicate vault tokens.
                completion(.failure(.networkError(error)))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse, let data else {
                completion(.failure(.invalidResponse))
                return
            }

            let statusCode = httpResponse.statusCode
            #if DEBUG
            print("[SecureFields] tokenize \(statusCode)")
            #endif

            if statusCode >= 500 && retries > 0 {
                self.perform(request: request, retries: retries - 1, completion: completion)
                return
            }

            guard (200..<300).contains(statusCode) else {
                let message = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Unknown error"
                completion(.failure(.apiError(message: message, statusCode: statusCode)))
                return
            }

            do {
                let result = try JSONDecoder().decode(TokenizationResponse.self, from: data)
                completion(.success(result))
            } catch {
                #if DEBUG
                print("[SecureFields] tokenize decode error: \(type(of: error))")
                #endif
                completion(.failure(.invalidResponse))
            }
        }.resume()
    }
}

private extension URLSessionConfiguration {
    static var pciSecure: URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return config
    }
}

// MARK: - SPKI Certificate Pinning

/// `URLSessionDelegate` that enforces SubjectPublicKeyInfo (SPKI) pinning.
/// Any server certificate whose public-key SHA-256 hash matches a pinned value is trusted;
/// all others are rejected, even if they have a valid chain to a system root CA.
///
/// Supported key types: RSA-2048, RSA-4096, EC-256 (P-256), EC-384 (P-384).
private final class PinningDelegate: NSObject, URLSessionDelegate {

    private let pinnedHashes: Set<String>

    init(hashes: [String]) {
        self.pinnedHashes = Set(hashes)
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            // Non-TLS challenge (e.g. client certificate) — reject
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Evaluate system trust first — reject expired / untrusted chains outright
        var cfError: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &cfError) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Walk the certificate chain; accept if any cert's public key matches a pin
        let certChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] ?? []
        for cert in certChain {
            if let hash = spkiHash(for: cert), pinnedHashes.contains(hash) {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }
        }

        // No pin matched — reject, even though system trust passed
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    // MARK: - SPKI hash computation

    /// Returns the Base64-encoded SHA-256 hash of the certificate's SubjectPublicKeyInfo DER encoding.
    private func spkiHash(for certificate: SecCertificate) -> String? {
        guard let publicKey = SecCertificateCopyKey(certificate) else { return nil }
        var cfError: Unmanaged<CFError>?
        guard let keyData = SecKeyCopyExternalRepresentation(publicKey, &cfError) as Data? else { return nil }
        guard let attrs = SecKeyCopyAttributes(publicKey) as? [CFString: Any] else { return nil }

        let keyType = attrs[kSecAttrKeyType] as? String ?? ""
        let keySize = attrs[kSecAttrKeySizeInBits] as? Int ?? 0
        guard let header = spkiHeader(type: keyType, size: keySize) else { return nil }

        let digest = SHA256.hash(data: header + keyData)
        return Data(digest).base64EncodedString()
    }

    /// Returns the fixed ASN.1 DER header that precedes the raw key bytes for a given key type/size.
    /// These are well-known constants (same as TrustKit / OkHttp CertificatePinner).
    private func spkiHeader(type: String, size: Int) -> Data? {
        // RSA keys
        if type == (kSecAttrKeyTypeRSA as String) {
            switch size {
            case 2048:
                return Data([0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09,
                             0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01,
                             0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00])
            case 4096:
                return Data([0x30, 0x82, 0x02, 0x22, 0x30, 0x0d, 0x06, 0x09,
                             0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01,
                             0x01, 0x05, 0x00, 0x03, 0x82, 0x02, 0x0f, 0x00])
            default:
                return nil
            }
        }

        // EC keys
        if type == (kSecAttrKeyTypeEC as String) {
            switch size {
            case 256: // P-256
                return Data([0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86,
                             0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a,
                             0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03,
                             0x42, 0x00])
            case 384: // P-384
                return Data([0x30, 0x76, 0x30, 0x10, 0x06, 0x07, 0x2a, 0x86,
                             0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x05, 0x2b,
                             0x81, 0x04, 0x00, 0x22, 0x03, 0x62, 0x00])
            default:
                return nil
            }
        }

        return nil
    }
}
