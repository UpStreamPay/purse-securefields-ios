import Foundation

/// A minimal JSON value used for remote log payloads — structural metadata only
/// (counts, codes, booleans), never card data.
enum JSONValue: Encodable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

/// Mirrors the wire type used by Purse's other SecureFields SDKs, so every platform
/// produces the same shape against the monitoring ingestion endpoint.
enum LogLevel: String, Encodable {
    case ok = "OK"
    case debug = "DEBUG"
    case verbose = "VERBOSE"
    case notice = "NOTICE"
    case warning = "WARNING"
    case error = "ERROR"
}

/// Mirrors the log codes used by Purse's other SecureFields SDKs.
enum LogCode {
    static let initSDK = "INIT_SDK"
    static let fieldFocus = "FIELD_FOCUS"
    static let fieldBlur = "FIELD_BLUR"
    static let brandDetected = "BRAND_DETECTED"
    static let brandNotDetected = "BRAND_NOT_DETECTED"
    static let brandSelectionChanged = "BRAND_SELECTION_CHANGED"
    static let submit = "SUBMIT"
    static let submitSuccess = "SUBMIT_SUCCESS"
    static let error = "ERROR"
    static let destroy = "DESTROY"
}

struct SecureFieldsLog: Encodable {
    let tenantId: String
    let instanceId: String
    let version: String
    let date: String
    let env: String
    let level: LogLevel
    let code: String
    let payload: [String: JSONValue]
    let platform = "ios"
}
