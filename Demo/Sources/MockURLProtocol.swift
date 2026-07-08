#if DEBUG
import Foundation

final class MockURLProtocol: URLProtocol {
    struct MockResponse {
        let data: Data
        let statusCode: Int
    }
    static var handlers: [String: MockResponse] = [:]

    /// Most recent request body per matched path-suffix key ("bin-lookup" / "secure-fields") —
    /// lets callers (the bug reproduction gallery) inspect exactly what the SDK sent over the
    /// wire, e.g. to display the `selected_network` or `birth_date` fields it actually submitted.
    static var capturedBodies: [String: Data] = [:]

    /// Optional hook fired synchronously from `startLoading()` (on whatever thread `URLSession`
    /// calls it from) with the matched key and raw body, before the mock response is delivered.
    static var onRequest: ((String, Data?) -> Void)?

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let key = Self.handlers.keys.first { path.hasSuffix($0) } ?? ""
        let body = Self.bodyData(from: request)
        if !key.isEmpty {
            Self.capturedBodies[key] = body
        }
        Self.onRequest?(key, body)

        guard let mock = Self.handlers[key] else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: mock.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: mock.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// `URLSession` frequently hands `URLProtocol` a request whose `httpBody` has already been
    /// converted to `httpBodyStream` (a well-known quirk of the session → protocol boundary), so
    /// both are checked here to reliably capture the body regardless of which one is populated.
    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
    }
}
#endif
