import Foundation

/// Separate, opt-out remote logger for the secure fields SDK. Forwards error/warn/info events
/// to the widget log worker for Datadog monitoring.
///
/// Events are sent continuously, as they happen — matching the web vault SDK's monitoring
/// proxy. PCI safety comes from every payload being structural metadata only (field names,
/// brand lists, outcome codes) and NEVER card data — never from a suppression window. No caller
/// of this class may ever place raw field values (PAN, CVV, expiry, cardholder name) in a log
/// payload.
final class RemoteLogger {

    private let tenantId: String
    private let version: String
    private let env: String
    private let instanceId: String
    private let enabled: Bool
    private let queue: LogQueue

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
        #if DEBUG
        if !self.enabled {
            print("[SecureFields] Remote log monitoring disabled (missing apiKey or monitoringEnabled=false)")
        }
        #endif

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
        guard enabled else { return }
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
