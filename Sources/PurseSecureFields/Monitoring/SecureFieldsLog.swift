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

/// Mirrors the web vault SDK's `SecureFieldsLog` wire type
/// (vault/packages/securefields-js-sdk/src/monitoring/types.ts) so both SDKs
/// produce the same shape against the `cf-widget-logger` `/logs/api/secure_fields` route.
enum LogLevel: String, Encodable {
    case ok = "OK"
    case debug = "DEBUG"
    case verbose = "VERBOSE"
    case notice = "NOTICE"
    case warning = "WARNING"
    case error = "ERROR"
}

enum LogCode {
    static let initSDK = "INIT_SDK"
    static let destroy = "DESTROY"
    static let error = "ERROR"
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
