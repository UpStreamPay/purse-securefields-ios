import Testing
import Foundation
@testable import PurseSecureFields

/// Captures the outgoing `URLRequest` instead of hitting the network, mirroring
/// `Demo/Sources/MockURLProtocol.swift` (not available to this target) so `RemoteLogClient`
/// can be tested via its `init(monitoringApiRoot:apiKey:session:)` test-only init.
///
/// Swift Testing runs tests in parallel, so callbacks are keyed by the request's `api-key` query
/// param (each test uses a unique one) rather than stored in a single shared closure — a plain
/// `static var onRequest` would race across concurrently-running tests.
final class RequestCapturingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var handlers: [String: (URLRequest) -> Void] = [:]

    static func register(apiKey: String, onRequest: @escaping (URLRequest) -> Void) {
        lock.lock(); handlers[apiKey] = onRequest; lock.unlock()
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RequestCapturingURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let apiKey = Self.apiKey(from: request.url) {
            Self.lock.lock()
            let handler = Self.handlers[apiKey]
            Self.lock.unlock()
            handler?(request)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func apiKey(from url: URL?) -> String? {
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        return components.queryItems?.first(where: { $0.name == "api-key" })?.value
    }

    static func body(of request: URLRequest) -> Data? {
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

struct RemoteLogClientTests {

    private func sampleEvent(code: String = "INIT_SDK") -> SecureFieldsLog {
        SecureFieldsLog(
            tenantId: "tenant-1",
            instanceId: "instance-1",
            version: "0.1.0",
            date: "2026-07-06T00:00:00Z",
            env: "sandbox",
            level: .ok,
            code: code,
            payload: ["brands": .array([.string("VISA")])]
        )
    }

    @Test func postsAJSONArrayWithApiKeyAsQueryParam() throws {
        let semaphore = DispatchSemaphore(value: 0)
        var captured: URLRequest?
        RequestCapturingURLProtocol.register(apiKey: "secret key") { request in
            captured = request
            semaphore.signal()
        }
        let client = RemoteLogClient(
            monitoringApiRoot: "https://api.example.com",
            apiKey: "secret key",
            session: RequestCapturingURLProtocol.makeSession()
        )

        client.send([sampleEvent()])
        #expect(semaphore.wait(timeout: .now() + 2) == .success)

        let request = try #require(captured)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/widget/secure_fields")
        #expect(request.url?.query == "api-key=secret%20key")

        let body = try #require(RequestCapturingURLProtocol.body(of: request))
        let array = try #require(try JSONSerialization.jsonObject(with: body) as? [[String: Any]])
        #expect(array.count == 1)
        #expect(array[0]["tenantId"] as? String == "tenant-1")
        #expect(array[0]["instanceId"] as? String == "instance-1")
        #expect(array[0]["platform"] as? String == "ios")
        #expect(array[0]["level"] as? String == "OK")
        #expect(array[0]["code"] as? String == "INIT_SDK")
    }

    @Test func sendsNothingForAnEmptyBatch() {
        var called = false
        RequestCapturingURLProtocol.register(apiKey: "empty-batch-key") { _ in called = true }
        let client = RemoteLogClient(
            monitoringApiRoot: "https://api.example.com",
            apiKey: "empty-batch-key",
            session: RequestCapturingURLProtocol.makeSession()
        )

        client.send([])

        #expect(!called)
    }
}
