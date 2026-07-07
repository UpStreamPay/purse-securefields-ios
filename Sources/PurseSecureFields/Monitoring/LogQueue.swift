import Foundation

/// Buffers log events and flushes them as a batch, mirroring the web vault SDK's
/// `SimpleQueue` (vault/packages/securefields-js-sdk/src/monitoring/queue.ts):
/// flush once `batchSize` events are queued, after `flushDelay` of inactivity,
/// or immediately if adding an event would exceed `maxBatchBytes`.
final class LogQueue {

    private let batchSize: Int
    private let flushDelay: TimeInterval
    private let maxBatchBytes: Int
    private let sender: ([SecureFieldsLog]) -> Void

    private let syncQueue = DispatchQueue(label: "eu.purse.securefields.log-queue")
    private var buffer: [SecureFieldsLog] = []
    private var bufferedBytes = 0
    private var pendingFlush: DispatchWorkItem?

    init(
        batchSize: Int = 16,
        flushDelay: TimeInterval = 2,
        maxBatchBytes: Int = 64_000,
        sender: @escaping ([SecureFieldsLog]) -> Void
    ) {
        self.batchSize = batchSize
        self.flushDelay = flushDelay
        self.maxBatchBytes = maxBatchBytes
        self.sender = sender
    }

    func enqueue(_ event: SecureFieldsLog) {
        syncQueue.async { [weak self] in
            self?.enqueueLocked(event)
        }
    }

    /// Sends any buffered events immediately and returns what was sent (for tests).
    @discardableResult
    func flush() -> [SecureFieldsLog] {
        syncQueue.sync {
            let batch = flushLocked()
            sendLocked(batch)
            return batch
        }
    }

    private func enqueueLocked(_ event: SecureFieldsLog) {
        let eventSize = encodedSize(of: event)

        if !buffer.isEmpty && bufferedBytes + eventSize > maxBatchBytes {
            sendLocked(flushLocked())
        }

        buffer.append(event)
        bufferedBytes += eventSize

        if buffer.count >= batchSize {
            sendLocked(flushLocked())
        } else {
            scheduleFlush()
        }
    }

    private func scheduleFlush() {
        guard pendingFlush == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.flushFromTimer()
        }
        pendingFlush = work
        syncQueue.asyncAfter(deadline: .now() + flushDelay, execute: work)
    }

    private func flushFromTimer() {
        pendingFlush = nil
        sendLocked(flushLocked())
    }

    private func flushLocked() -> [SecureFieldsLog] {
        pendingFlush?.cancel()
        pendingFlush = nil
        let batch = buffer
        buffer = []
        bufferedBytes = 0
        return batch
    }

    private func sendLocked(_ batch: [SecureFieldsLog]) {
        guard !batch.isEmpty else { return }
        sender(batch)
    }

    private func encodedSize(of event: SecureFieldsLog) -> Int {
        (try? JSONEncoder().encode(event).count) ?? 0
    }
}
