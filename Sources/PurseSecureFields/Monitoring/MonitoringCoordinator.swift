import Foundation

/// Bridges `SecureFieldsManager`'s submit lifecycle to `RemoteLogger`, mirroring the web vault
/// SDK's `WithMonitoringProxy`: telemetry is derived by observing submit start/result — the same
/// two points `SecureFieldsManager` already reports to its own delegate — rather than storing
/// counters as `SecureFieldsManager`'s own properties. `SecureFieldsManager` only ever calls
/// `start`, `mount`, `unmount`, `recordSubmitStart`, `recordSubmitSuccess`, and
/// `recordSubmitFailure` — everything else (payload shape, the submit-outcome summary) lives here.
final class MonitoringCoordinator {

    private let logger: RemoteLogger

    // Session-summary counters for the DESTROY log — never card data, counts/codes only.
    private var submitAttempts = 0
    private var submitSuccessCount = 0
    private var submitErrorCodes: [String] = []

    init(
        tenantId: String,
        version: String,
        env: String,
        monitoringApiRoot: String,
        apiKey: String?,
        monitoringEnabled: Bool = true,
        logger: RemoteLogger? = nil
    ) {
        self.logger = logger ?? RemoteLogger(
            tenantId: tenantId,
            version: version,
            env: env,
            monitoringApiRoot: monitoringApiRoot,
            apiKey: apiKey,
            monitoringEnabled: monitoringEnabled
        )
    }

    func start(config: SecureFieldsConfig) {
        logger.info(LogCode.initSDK, payload: [
            "brands": .array(config.brands.map { .string($0.rawValue) }),
        ])
    }

    /// PCI: suppress all remote logging for as long as the secure fields are on screen.
    func mount() {
        logger.mounted = true
    }

    /// Fields are torn down — safe to resume logging, emit the session summary, and flush.
    func unmount() {
        logger.mounted = false
        logger.info(LogCode.destroy, payload: [
            "submitAttempts": .int(submitAttempts),
            "submitSuccesses": .int(submitSuccessCount),
            "submitErrorCodes": .array(submitErrorCodes.map { .string($0) }),
        ])
        logger.flush()
    }

    func flush() {
        logger.flush()
    }

    func recordSubmitStart() {
        submitAttempts += 1
    }

    func recordSubmitSuccess() {
        submitSuccessCount += 1
    }

    func recordSubmitFailure(_ error: SecureFieldsError) {
        submitErrorCodes.append(Self.errorCode(for: error))
    }

    /// A short, non-sensitive tag for the DESTROY session summary — never the error message,
    /// which could (in principle) echo back arbitrary server-provided text.
    private static func errorCode(for error: SecureFieldsError) -> String {
        switch error {
        case .fieldsIncomplete: return "FIELDS_INCOMPLETE"
        case .networkError: return "NETWORK_ERROR"
        case .apiError(_, let statusCode): return String(statusCode)
        case .invalidResponse: return "INVALID_RESPONSE"
        }
    }
}
