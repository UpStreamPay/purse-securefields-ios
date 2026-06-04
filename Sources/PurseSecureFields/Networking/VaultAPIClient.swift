import Foundation

final class VaultAPIClient {

    static let sdkVersion = "0.1.0"

    private let baseURL: String
    private let session: URLSession
    private let maxRetries = 3

    init(baseURL: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func binLookup(
        tenantId: String,
        firstDigits: String,
        completion: @escaping (Result<BinLookupResult, SecureFieldsError>) -> Void
    ) {
        let urlString = "\(baseURL)/v1/tenants/\(tenantId)/bin-lookup"
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

            guard let data else {
                completion(.failure(.invalidResponse))
                return
            }
            let result = (try? JSONDecoder().decode(BinLookupResponse.self, from: data))?.toBinLookupResult()
                ?? BinLookupResult(brands: [], panLengths: [16], cvvLengths: [3])
            completion(.success(result))
        }.resume()
    }

    func tokenize(
        tenantId: String,
        payload: TokenizationPayload,
        completion: @escaping (Result<TokenizationResponse, SecureFieldsError>) -> Void
    ) {
        let urlString = "\(baseURL)/v1/tenants/\(tenantId)/forms/secure-fields"
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
                if retries > 0 {
                    self.perform(request: request, retries: retries - 1, completion: completion)
                } else {
                    completion(.failure(.networkError(error)))
                }
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
                print("[SecureFields] tokenize decode error: \(error)")
                #endif
                completion(.failure(.invalidResponse))
            }
        }.resume()
    }
}
