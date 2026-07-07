import Foundation

/// Separate, opt-out remote logger for the secure fields SDK. Forwards error/warn/info events
/// to the widget log worker for Datadog monitoring.
///
/// PCI: while `mounted` is `true` (i.e. while the secure fields are on screen), all logging is
/// suppressed — nothing is ever sent between `SecureFieldsManager.init` and `deinit`. No card
/// data is ever placed in a log payload by any caller of this class.
final class RemoteLogger {

    private let tenantId: String
    private let version: String
    private let env: String
    private let instanceId: String
    private let enabled: Bool
    private let queue: LogQueue

    /// Toggles PCI suppression. `true` for the entire lifetime the secure fields are on screen.
    var mounted = false

    init(
        tenantId: String,
        version: String,
        env: String,
        monitoringApiRoot: String,
        apiKey: String?,
        monitoringEnabled: Bool = true,
        instanceId: String = UUID().uuidString,
        batchSize: Int = 16,
        flushDelay: TimeInterval = 2,
        maxBatchBytes: Int = 64_000,
        client: RemoteLogClient? = nil
    ) {
        self.tenantId = tenantId
        self.version = version
        self.env = env
        self.instanceId = instanceId

        let resolvedClient: RemoteLogClient?
        if let client {
            resolvedClient = client
        } else if monitoringEnabled, let apiKey, !apiKey.isEmpty {
            resolvedClient = RemoteLogClient(monitoringApiRoot: monitoringApiRoot, apiKey: apiKey)
        } else {
            resolvedClient = nil
        }
        self.enabled = resolvedClient != nil

        self.queue = LogQueue(batchSize: batchSize, flushDelay: flushDelay, maxBatchBytes: maxBatchBytes) { events in
            resolvedClient?.send(events)
        }
    }

    func info(_ code: String, payload: [String: JSONValue] = [:]) { log(.ok, code, payload) }
    func warn(_ code: String, payload: [String: JSONValue] = [:]) { log(.warning, code, payload) }
    func error(_ code: String, payload: [String: JSONValue] = [:]) { log(.error, code, payload) }

    @discardableResult
    func flush() -> [SecureFieldsLog] { queue.flush() }

    private func log(_ level: LogLevel, _ code: String, _ payload: [String: JSONValue]) {
        guard enabled, !mounted else { return }
        queue.enqueue(
            SecureFieldsLog(
                tenantId: tenantId,
                instanceId: instanceId,
                version: version,
                date: Self.dateFormatter.string(from: Date()),
                env: env,
                level: level,
                code: code,
                payload: payload
            )
        )
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
