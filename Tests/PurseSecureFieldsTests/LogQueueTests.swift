import Testing
import Foundation
@testable import PurseSecureFields

struct LogQueueTests {

    private func event(_ code: String, payload: [String: JSONValue] = [:]) -> SecureFieldsLog {
        SecureFieldsLog(
            tenantId: "t", instanceId: "i", version: "0.1.0", date: "2026-07-06T00:00:00Z",
            env: "sandbox", level: .ok, code: code, payload: payload
        )
    }

    @Test func flushesAutomaticallyOnceBatchSizeIsReached() {
        let lock = NSLock()
        var sentBatches: [[SecureFieldsLog]] = []
        let semaphore = DispatchSemaphore(value: 0)
        let queue = LogQueue(batchSize: 3, flushDelay: 10) { batch in
            lock.lock(); sentBatches.append(batch); lock.unlock()
            semaphore.signal()
        }

        queue.enqueue(event("A"))
        queue.enqueue(event("B"))
        queue.enqueue(event("C"))

        #expect(semaphore.wait(timeout: .now() + 2) == .success)
        lock.lock(); let result = sentBatches; lock.unlock()
        #expect(result.count == 1)
        #expect(result.first?.count == 3)
    }

    @Test func flushesAfterTheInactivityDelayEvenBelowBatchSize() {
        let lock = NSLock()
        var sentBatches: [[SecureFieldsLog]] = []
        let semaphore = DispatchSemaphore(value: 0)
        let queue = LogQueue(batchSize: 16, flushDelay: 0.05) { batch in
            lock.lock(); sentBatches.append(batch); lock.unlock()
            semaphore.signal()
        }

        queue.enqueue(event("A"))

        #expect(semaphore.wait(timeout: .now() + 2) == .success)
        lock.lock(); let result = sentBatches; lock.unlock()
        #expect(result.count == 1)
        #expect(result.first?.count == 1)
    }

    @Test func flushesEarlyWhenTheByteBudgetWouldBeExceeded() {
        let lock = NSLock()
        var sentBatches: [[SecureFieldsLog]] = []
        let semaphore = DispatchSemaphore(value: 0)
        let bigPayload: [String: JSONValue] = ["blob": .string(String(repeating: "x", count: 100))]
        let queue = LogQueue(batchSize: 16, flushDelay: 10, maxBatchBytes: 150) { batch in
            lock.lock(); sentBatches.append(batch); lock.unlock()
            semaphore.signal()
        }

        queue.enqueue(event("A", payload: bigPayload))
        queue.enqueue(event("B", payload: bigPayload))

        #expect(semaphore.wait(timeout: .now() + 2) == .success)
        lock.lock(); let result = sentBatches; lock.unlock()
        #expect(result.count == 1)
        #expect(result.first?.count == 1)
        #expect(result.first?.first?.code == "A")
    }

    @Test func manualFlushSendsTheBufferedBatchAndClearsIt() {
        var sentBatches: [[SecureFieldsLog]] = []
        let queue = LogQueue(batchSize: 16, flushDelay: 10) { sentBatches.append($0) }

        queue.enqueue(event("A"))
        let firstFlush = queue.flush()

        #expect(firstFlush.count == 1)
        #expect(sentBatches.count == 1)
        #expect(queue.flush().isEmpty)
    }
}
