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

    /// Takes the merchant's own `submit` arguments, not the network the SDK resolves from them.
    ///
    /// The payload matches the web vault SDK's SUBMIT log, `{ arg0: { selectedNetwork, saveToken } }`,
    /// so one collector query covers every platform. Only these two: the card data is never passed
    /// here, and nothing else should land in the logs by default.
    func recordSubmitStart(selectedNetwork: CardBrand? = nil, saveToken: Bool = false) {
        submitAttempts += 1
        var options: [String: JSONValue] = ["saveToken": .bool(saveToken)]
        if let selectedNetwork {
            options["selectedNetwork"] = .string(selectedNetwork.rawValue)
        }
        logger.info(LogCode.submit, payload: ["arg0": .object(options)])
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
        // The case name only — a `ThreeDSError` can carry provider or gateway text in its
        // associated values, and none of it belongs in a log payload.
        case .threeDS(let threeDSError): return Self.threeDSCode(for: threeDSError)
        }
    }

    private static func threeDSCode(for error: ThreeDSError) -> String {
        switch error {
        case .providerUnavailable: return "THREEDS_PROVIDER_UNAVAILABLE"
        case .configurationMissing: return "THREEDS_CONFIGURATION_MISSING"
        case .initializationFailed: return "THREEDS_INIT_FAILED"
        case .cardNotEligible: return "THREEDS_CARD_NOT_ELIGIBLE"
        case .notConfigured: return "THREEDS_NOT_CONFIGURED"
        case .versioningFailed(let statusCode, _): return "THREEDS_VERSIONING_\(statusCode)"
        case .challengeResultFailed(let statusCode, _): return "THREEDS_CHALLENGE_RESULT_\(statusCode)"
        case .transactionFailed: return "THREEDS_TRANSACTION_FAILED"
        case .invalidEphemeralKey: return "THREEDS_INVALID_EPHEMERAL_KEY"
        case .invalidChallengeData: return "THREEDS_INVALID_CHALLENGE_DATA"
        case .noActiveTransaction: return "THREEDS_NO_ACTIVE_TRANSACTION"
        case .challengeInProgress: return "THREEDS_CHALLENGE_IN_PROGRESS"
        case .networkError: return "THREEDS_NETWORK_ERROR"
        }
    }
}
