import Foundation

/// Stubs the vault gateway (`/bin-lookup` and `/forms/secure-fields`) and records every request,
/// so manager- and client-level tests can exercise success paths fully offline — the counterpart
/// of `FailingURLProtocol`, which can only exercise failures.
///
/// Swift Testing runs tests in parallel, so handlers and captured requests are keyed by the
/// tenant id embedded in the URL path (each test uses a unique one) rather than stored in shared
/// statics — the same discipline as `RequestCapturingURLProtocol`.
final class StubGatewayURLProtocol: URLProtocol {

    struct Stub {
        let statusCode: Int
        let body: String
    }

    private static let lock = NSLock()
    private static var handlers: [String: (URLRequest, Data?) -> Stub] = [:]
    private static var captured: [String: [(request: URLRequest, body: Data?)]] = [:]

    /// The handler receives the request together with its body — already drained from the
    /// stream, since `URLRequest.httpBody` is always nil by the time a protocol sees it.
    static func register(tenantId: String, handler: @escaping (URLRequest, Data?) -> Stub) {
        lock.lock(); handlers[tenantId] = handler; lock.unlock()
    }

    /// Every request seen for this tenant, with its body already drained from the stream.
    static func requests(tenantId: String) -> [(request: URLRequest, body: Data?)] {
        lock.lock(); defer { lock.unlock() }
        return captured[tenantId] ?? []
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubGatewayURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let tenantId = Self.tenantId(from: request.url)
        let body = Self.drainBody(of: request)

        Self.lock.lock()
        if let tenantId {
            Self.captured[tenantId, default: []].append((request, body))
        }
        let handler = tenantId.flatMap { Self.handlers[$0] }
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let stub = handler(request, body)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// The path component after "tenants" — `/v1/tenants/{tenantId}/...`.
    private static func tenantId(from url: URL?) -> String? {
        guard let components = url?.pathComponents,
              let index = components.firstIndex(of: "tenants"),
              components.indices.contains(index + 1) else { return nil }
        return components[index + 1]
    }

    /// URLSession hands the body to protocols as a stream, never as `httpBody`.
    private static func drainBody(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
