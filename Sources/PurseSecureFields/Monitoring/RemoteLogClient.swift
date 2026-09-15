import Foundation

/// Sends batches of `SecureFieldsLog` events to Purse's monitoring ingestion endpoint
/// (the `/widget/secure_fields` route), which forwards them to Datadog.
/// Fire-and-forget: never throws, never retries, and is kept
/// separate from `VaultAPIClient` so a telemetry failure can never affect PCI flows.
final class RemoteLogClient {

    private let monitoringURL: URL?
    private let apiKey: String
    private let session: URLSession

    /// Production init — creates an ephemeral, cache-free session.
    init(monitoringApiRoot: String, apiKey: String) {
        self.apiKey = apiKey
        self.monitoringURL = URL(string: "\(monitoringApiRoot)/widget/secure_fields")
        self.session = URLSession(configuration: .pciSecureLogging)
    }

    /// Test-only init — bypasses the production session.
    init(monitoringApiRoot: String, apiKey: String, session: URLSession) {
        self.apiKey = apiKey
        self.monitoringURL = URL(string: "\(monitoringApiRoot)/widget/secure_fields")
        self.session = session
    }

    func send(_ events: [SecureFieldsLog]) {
        guard !events.isEmpty, let monitoringURL else { return }
        guard var components = URLComponents(url: monitoringURL, resolvingAgainstBaseURL: false) else { return }
        components.queryItems = [URLQueryItem(name: "api-key", value: apiKey)]
        guard let url = components.url, let body = try? JSONEncoder().encode(events) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        session.dataTask(with: request) { _, _, _ in
            // Fire-and-forget: no retry, no error propagation to the caller.
        }.resume()
    }
}

private extension URLSessionConfiguration {
    static var pciSecureLogging: URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 5
        return config
    }
}
