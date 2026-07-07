import Testing
import Foundation
@testable import PurseSecureFields

struct RemoteLoggerTests {

    // RemoteLogClient.send() hits the network asynchronously even against a mock URLProtocol,
    // so a semaphore signalled per captured request makes waiting for it deterministic. Each
    // call gets its own random api-key so parallel tests never share a request-capturing slot
    // (this key never needs to match RemoteLogger's own `apiKey:` param — when a `client`
    // override is supplied, RemoteLogger never looks at that param).
    private func capturingClient(onRequest: @escaping (URLRequest) -> Void) -> RemoteLogClient {
        let key = UUID().uuidString
        RequestCapturingURLProtocol.register(apiKey: key, onRequest: onRequest)
        return RemoteLogClient(
            monitoringApiRoot: "https://api.example.com",
            apiKey: key,
            session: RequestCapturingURLProtocol.makeSession()
        )
    }

    private func logger(client: RemoteLogClient?, monitoringEnabled: Bool = true, apiKey: String? = "key") -> RemoteLogger {
        RemoteLogger(
            tenantId: "tenant-1",
            version: "0.1.0",
            env: "sandbox",
            monitoringApiRoot: "https://api.example.com",
            apiKey: apiKey,
            monitoringEnabled: monitoringEnabled,
            batchSize: 1,
            client: client
        )
    }

    @Test func sendsInfoWarnAndErrorAtTheCorrectLevel() {
        let lock = NSLock()
        var levels: [String] = []
        let semaphore = DispatchSemaphore(value: 0)
        let client = capturingClient { request in
            if let body = RequestCapturingURLProtocol.body(of: request),
               let array = try? JSONSerialization.jsonObject(with: body) as? [[String: Any]],
               let level = array.first?["level"] as? String {
                lock.lock(); levels.append(level); lock.unlock()
            }
            semaphore.signal()
        }
        let sut = logger(client: client)

        sut.info("INIT_SDK")
        #expect(semaphore.wait(timeout: .now() + 2) == .success)
        sut.warn("SOME_WARNING")
        #expect(semaphore.wait(timeout: .now() + 2) == .success)
        sut.error("SOME_ERROR")
        #expect(semaphore.wait(timeout: .now() + 2) == .success)

        lock.lock(); let result = levels; lock.unlock()
        #expect(result == ["OK", "WARNING", "ERROR"])
    }

    @Test func suppressesAllLoggingWhileMounted() {
        var sendCount = 0
        let lock = NSLock()
        let semaphore = DispatchSemaphore(value: 0)
        let client = capturingClient { _ in
            lock.lock(); sendCount += 1; lock.unlock()
            semaphore.signal()
        }
        let sut = logger(client: client)

        // Suppressed while mounted: log() returns before ever touching the queue, so there is
        // nothing in flight to race against here.
        sut.mounted = true
        sut.info("SHOULD_NOT_SEND")
        sut.error("SHOULD_NOT_SEND_EITHER")
        lock.lock(); #expect(sendCount == 0); lock.unlock()

        sut.mounted = false
        sut.info("SHOULD_SEND")
        #expect(semaphore.wait(timeout: .now() + 2) == .success)
        lock.lock(); #expect(sendCount == 1); lock.unlock()
    }

    @Test func isDisabledWhenApiKeyIsMissing() {
        var called = false
        RequestCapturingURLProtocol.register(apiKey: UUID().uuidString) { _ in called = true }
        // No client override and no apiKey — RemoteLogger must never construct a client itself.
        let sut = logger(client: nil, apiKey: nil)

        sut.info("SHOULD_NOT_SEND")

        #expect(!called)
    }

    @Test func isDisabledWhenMonitoringEnabledIsFalse() {
        var called = false
        let client = capturingClient { _ in called = true }
        let sut = logger(client: client, monitoringEnabled: false)

        sut.info("SHOULD_NOT_SEND")

        #expect(!called)
    }

    @Test func flushSendsBufferedEventsImmediately() {
        let semaphore = DispatchSemaphore(value: 0)
        let client = capturingClient { _ in semaphore.signal() }
        // batchSize large enough that only the manual flush sends it.
        let sut = RemoteLogger(
            tenantId: "tenant-1", version: "0.1.0", env: "sandbox",
            monitoringApiRoot: "https://api.example.com", apiKey: "key",
            batchSize: 16, client: client
        )

        sut.info("BUFFERED")
        let flushed = sut.flush()
        #expect(flushed.count == 1)
        #expect(semaphore.wait(timeout: .now() + 2) == .success)
    }
}
