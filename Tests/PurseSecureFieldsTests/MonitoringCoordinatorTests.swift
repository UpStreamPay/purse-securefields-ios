import Testing
import Foundation
@testable import PurseSecureFields

/// MonitoringCoordinator is what keeps SecureFieldsManager itself free of monitoring plumbing —
/// SecureFieldsManager only calls start()/unmount()/record*(), the same hook points it already
/// reports to its own delegate. All counters and payload-building live here instead. Events are
/// sent as they happen — there is no suppression window, matching the web vault SDK.
struct MonitoringCoordinatorTests {

    // batchSize: 1 so every record*() call auto-flushes as its own request — lets tests wait on
    // the semaphore immediately after each call and assert against captured requests in order.
    private func coordinator(onRequest: @escaping (URLRequest) -> Void) -> MonitoringCoordinator {
        let key = UUID().uuidString
        RequestCapturingURLProtocol.register(apiKey: key, onRequest: onRequest)
        let client = RemoteLogClient(
            monitoringApiRoot: "https://api.example.com",
            apiKey: key,
            session: RequestCapturingURLProtocol.makeSession()
        )
        let logger = RemoteLogger(
            tenantId: "tenant-1", version: "0.1.0", env: "sandbox",
            monitoringApiRoot: "https://api.example.com", apiKey: key,
            batchSize: 1, client: client
        )
        return MonitoringCoordinator(
            tenantId: "tenant-1", version: "0.1.0", env: "sandbox",
            monitoringApiRoot: "https://api.example.com", apiKey: key,
            logger: logger
        )
    }

    private func minimalConfig() -> SecureFieldsConfig {
        SecureFieldsConfig(tenantId: "tenant-1", environment: .sandbox, brands: [.visa, .mastercard])
    }

    private func code(of request: URLRequest) throws -> String {
        let body = try #require(RequestCapturingURLProtocol.body(of: request))
        let event = try #require((try JSONSerialization.jsonObject(with: body) as? [[String: Any]])?.first)
        return try #require(event["code"] as? String)
    }

    @Test func startSendsAnInitSDKLogWithBrandsFromConfig() throws {
        let semaphore = DispatchSemaphore(value: 0)
        var captured: URLRequest?
        let sut = coordinator { request in
            captured = request
            semaphore.signal()
        }

        sut.start(config: minimalConfig())

        #expect(semaphore.wait(timeout: .now() + 2) == .success)
        let request = try #require(captured)
        let body = try #require(RequestCapturingURLProtocol.body(of: request))
        let event = try #require((try JSONSerialization.jsonObject(with: body) as? [[String: Any]])?.first)
        #expect(event["code"] as? String == "INIT_SDK")
        let brands = try #require((event["payload"] as? [String: Any])?["brands"] as? [String])
        #expect(brands == ["VISA", "MASTERCARD"])
    }

    @Test func submitStartAndResultAreSentImmediatelyAndStillLandInTheDestroySummary() throws {
        let semaphore = DispatchSemaphore(value: 0)
        var captured: [URLRequest] = []
        let lock = NSLock()
        let sut = coordinator { request in
            lock.lock(); captured.append(request); lock.unlock()
            semaphore.signal()
        }

        // Exactly how SecureFieldsManager drives this: explicit one-line hook calls at the same
        // points it already reports to its own delegate — MonitoringCoordinator's counters are
        // never touched directly by anything else. Each call sends immediately (no suppression).
        sut.recordSubmitStart()
        #expect(semaphore.wait(timeout: .now() + 2) == .success)
        sut.recordSubmitSuccess()
        #expect(semaphore.wait(timeout: .now() + 2) == .success)
        sut.recordSubmitStart()
        #expect(semaphore.wait(timeout: .now() + 2) == .success)
        sut.recordSubmitFailure(.apiError(message: "declined", statusCode: 400))
        #expect(semaphore.wait(timeout: .now() + 2) == .success)
        sut.unmount()
        #expect(semaphore.wait(timeout: .now() + 2) == .success)

        lock.lock(); let requests = captured; lock.unlock()
        #expect(try code(of: requests[0]) == "SUBMIT")
        #expect(try code(of: requests[1]) == "SUBMIT_SUCCESS")
        #expect(try code(of: requests[2]) == "SUBMIT")
        #expect(try code(of: requests[3]) == "ERROR")

        let destroyBody = try #require(RequestCapturingURLProtocol.body(of: requests[4]))
        let destroyEvent = try #require((try JSONSerialization.jsonObject(with: destroyBody) as? [[String: Any]])?.first)
        #expect(destroyEvent["code"] as? String == "DESTROY")
        let payload = try #require(destroyEvent["payload"] as? [String: Any])
        #expect(payload["submitAttempts"] as? Int == 2)
        #expect(payload["submitSuccesses"] as? Int == 1)
        #expect((payload["submitErrorCodes"] as? [String])?.first == "400")
    }

    @Test func focusAndBlurAreSentImmediately() throws {
        let semaphore = DispatchSemaphore(value: 0)
        var captured: [URLRequest] = []
        let lock = NSLock()
        let sut = coordinator { request in
            lock.lock(); captured.append(request); lock.unlock()
            semaphore.signal()
        }

        sut.recordFocusChanged(field: .pan, isFocused: true)
        #expect(semaphore.wait(timeout: .now() + 2) == .success)
        sut.recordFocusChanged(field: .pan, isFocused: false)
        #expect(semaphore.wait(timeout: .now() + 2) == .success)

        lock.lock(); let requests = captured; lock.unlock()
        #expect(try code(of: requests[0]) == "FIELD_FOCUS")
        #expect(try code(of: requests[1]) == "FIELD_BLUR")
    }

    @Test func brandsDetectedAndNotDetectedAreSentImmediately() throws {
        let semaphore = DispatchSemaphore(value: 0)
        var captured: [URLRequest] = []
        let lock = NSLock()
        let sut = coordinator { request in
            lock.lock(); captured.append(request); lock.unlock()
            semaphore.signal()
        }

        sut.recordBrandsDetected([.visa])
        #expect(semaphore.wait(timeout: .now() + 2) == .success)
        sut.recordBrandsDetected([])
        #expect(semaphore.wait(timeout: .now() + 2) == .success)

        lock.lock(); let requests = captured; lock.unlock()
        let detectedBody = try #require(RequestCapturingURLProtocol.body(of: requests[0]))
        let detectedEvent = try #require((try JSONSerialization.jsonObject(with: detectedBody) as? [[String: Any]])?.first)
        #expect(detectedEvent["code"] as? String == "BRAND_DETECTED")
        #expect(detectedEvent["level"] as? String == "OK")
        #expect(try code(of: requests[1]) == "BRAND_NOT_DETECTED")
    }
}
