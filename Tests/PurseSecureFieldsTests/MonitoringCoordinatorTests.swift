import Testing
import Foundation
@testable import PurseSecureFields

/// MonitoringCoordinator is what keeps SecureFieldsManager itself free of monitoring plumbing —
/// SecureFieldsManager only calls start()/mount()/unmount()/recordSubmitStart()/
/// recordSubmitSuccess()/recordSubmitFailure(), the same hook points it already reports to its
/// own delegate. All counters and payload-building live here instead.
struct MonitoringCoordinatorTests {

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
        SecureFieldsConfig(tenantId: "tenant-1", baseURL: "https://api.vault.purse-sandbox.com", brands: [.visa, .mastercard])
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

    @Test func submitOutcomesRecordedThroughHooksLandInTheDestroySummary() throws {
        let semaphore = DispatchSemaphore(value: 0)
        var captured: URLRequest?
        let sut = coordinator { request in
            captured = request
            semaphore.signal()
        }

        // Exactly how SecureFieldsManager drives this: explicit one-line hook calls at the same
        // points it already reports to its own delegate — MonitoringCoordinator's counters are
        // never touched directly by anything else.
        sut.recordSubmitStart()
        sut.recordSubmitSuccess()
        sut.recordSubmitStart()
        sut.recordSubmitFailure(.apiError(message: "declined", statusCode: 400))

        sut.unmount()

        #expect(semaphore.wait(timeout: .now() + 2) == .success)
        let request = try #require(captured)
        let body = try #require(RequestCapturingURLProtocol.body(of: request))
        let event = try #require((try JSONSerialization.jsonObject(with: body) as? [[String: Any]])?.first)
        #expect(event["code"] as? String == "DESTROY")
        let payload = try #require(event["payload"] as? [String: Any])
        #expect(payload["submitAttempts"] as? Int == 2)
        #expect(payload["submitSuccesses"] as? Int == 1)
        #expect((payload["submitErrorCodes"] as? [String])?.first == "400")
    }

    @Test func mountSuppressesLoggingUntilUnmount() {
        var sendCount = 0
        let lock = NSLock()
        let semaphore = DispatchSemaphore(value: 0)
        let sut = coordinator { _ in
            lock.lock(); sendCount += 1; lock.unlock()
            semaphore.signal()
        }

        sut.mount()
        sut.recordSubmitStart()
        sut.recordSubmitSuccess()
        lock.lock(); #expect(sendCount == 0); lock.unlock()

        sut.unmount()

        #expect(semaphore.wait(timeout: .now() + 2) == .success)
        lock.lock(); #expect(sendCount == 1); lock.unlock()
    }
}
