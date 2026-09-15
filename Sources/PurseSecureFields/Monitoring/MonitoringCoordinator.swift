import Foundation

/// Bridges `SecureFieldsManager`'s event points to `RemoteLogger`:
/// telemetry is derived by observing events at the same points
/// `SecureFieldsManager` already reports to its own delegate, rather than storing counters as
/// `SecureFieldsManager`'s own properties. `SecureFieldsManager` only ever calls the `record*`
/// methods below plus `start`/`unmount` — everything else (payload shape, log codes, the
/// DESTROY session summary) lives here.
///
/// Events are sent as they happen — there is no suppression window.
/// Every payload built here is structural metadata only (field names, brand lists, outcome
/// codes); no caller ever has access to raw field values in the first place.
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
        // Field *names* only — which fields the form renders (e.g. a CVV-only form), never values.
        let fields = config.fields.configuredFields.map { String(describing: $0) }.sorted()
        logger.info(LogCode.initSDK, payload: [
            "brands": .array(config.brands.map { .string($0.rawValue) }),
            "fields": .array(fields.map { .string($0) }),
        ])
    }

    /// Fields are torn down — emit the session summary and flush.
    func unmount() {
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

    func recordFocusChanged(field: SecureField, isFocused: Bool) {
        logger.info(isFocused ? LogCode.fieldFocus : LogCode.fieldBlur, payload: [
            "fieldName": .string(String(describing: field)),
        ])
    }

    func recordBrandsDetected(_ brands: [CardBrand]) {
        if brands.isEmpty {
            logger.warn(LogCode.brandNotDetected)
        } else {
            logger.info(LogCode.brandDetected, payload: [
                "brands": .array(brands.map { .string($0.rawValue) }),
            ])
        }
    }

    func recordBrandSelected(_ brand: CardBrand) {
        logger.info(LogCode.brandSelectionChanged, payload: ["brand": .string(brand.rawValue)])
    }

    func recordBinLookupFailed(_ error: SecureFieldsError) {
        logger.error(LogCode.error, payload: [
            "code": .string(Self.errorCode(for: error)),
            "source": .string("BIN_LOOKUP"),
        ])
    }

    func recordSubmitStart() {
        submitAttempts += 1
        logger.info(LogCode.submit)
    }

    func recordSubmitSuccess() {
        submitSuccessCount += 1
        logger.info(LogCode.submitSuccess)
    }

    func recordSubmitFailure(_ error: SecureFieldsError) {
        let code = Self.errorCode(for: error)
        submitErrorCodes.append(code)
        logger.error(LogCode.error, payload: ["code": .string(code)])
    }

    /// A short, non-sensitive tag — never the error message, which could (in principle) echo
    /// back arbitrary server-provided text.
    private static func errorCode(for error: SecureFieldsError) -> String {
        switch error {
        case .fieldsIncomplete: return "FIELDS_INCOMPLETE"
        case .networkError: return "NETWORK_ERROR"
        case .apiError(_, let statusCode): return String(statusCode)
        case .invalidResponse: return "INVALID_RESPONSE"
        }
    }
}
