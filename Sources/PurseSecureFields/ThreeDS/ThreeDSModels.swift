import Foundation

// MARK: - The `sdk` block

/// The EMVCo SDK block the merchant backend sends in place of the web `browser` block:
/// `partner_data.sdk` on a session `validate`, a top-level `sdk` on `POST /v2/payments`.
///
/// snake_case on the wire, the `sdk` prefix dropped exactly as the web block drops `browser`.
/// `sdkMaxTimeout` and `deviceRenderOptions` are not part of it — Purse sets both server-side.
///
/// Forward it **verbatim**: it is `Encodable`, so `JSONEncoder().encode(result.sdk)` is the whole
/// hand-off.
public struct ThreeDSSDKBlock: Encodable, Equatable {
    public let appID: String
    public let transactionID: String
    public let referenceNumber: String
    /// The device-data JWE.
    public let encryptedData: String
    /// A JWK **object** (`kty`, `crv`, `x`, `y`), never the SDK's JSON string: the gateway
    /// answers a 400 on `/sdk/ephemeral_public_key` for a string there.
    public let ephemeralPublicKey: [String: String]

    enum CodingKeys: String, CodingKey {
        case appID = "app_id"
        case transactionID = "transaction_id"
        case referenceNumber = "reference_number"
        case encryptedData = "encrypted_data"
        case ephemeralPublicKey = "ephemeral_public_key"
    }

    public init(
        appID: String,
        transactionID: String,
        referenceNumber: String,
        encryptedData: String,
        ephemeralPublicKey: [String: String]
    ) {
        self.appID = appID
        self.transactionID = transactionID
        self.referenceNumber = referenceNumber
        self.encryptedData = encryptedData
        self.ephemeralPublicKey = ephemeralPublicKey
    }

    /// Maps the 3DS SDK's authentication request parameters onto the wire block.
    ///
    /// - Throws: `ThreeDSError.invalidEphemeralKey` when `sdkEphemeralPublicKey` is not a JSON
    ///   object of strings — sending it on as a string would be refused by the gateway anyway,
    ///   and a 400 at payment time is far harder to read than a failure here.
    init(parameters: ThreeDSAuthenticationRequestParameters) throws {
        guard let data = parameters.sdkEphemeralPublicKey.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ThreeDSError.invalidEphemeralKey
        }
        let jwk = object.compactMapValues { $0 as? String }
        guard !jwk.isEmpty, jwk.count == object.count else { throw ThreeDSError.invalidEphemeralKey }
        self.init(
            appID: parameters.sdkAppID,
            transactionID: parameters.sdkTransactionID,
            referenceNumber: parameters.sdkReferenceNumber,
            encryptedData: parameters.deviceData,
            ephemeralPublicKey: jwk
        )
    }
}

// MARK: - Versioning

/// Which card `POST /v2/3ds/versioning` is asked about. `device_channel` is always `APP` and is
/// added by the client: absent, the server versions a **browser** transaction, whose answer the
/// app cannot use and whose `sdk` block is refused later.
enum ThreeDSVersioningSubject {
    /// Fresh card, both flows — the form just tokenized.
    case freshCard(tenantId: String, formToken: String)
    /// Saved card, session flow.
    case savedCardSession(walletTokenId: String, clientSessionId: String)
    /// Saved card, advanced flow.
    case savedCardAdvanced(walletTokenId: String, entityId: String, customerReference: String)
}

/// The saved card a `submitSavedCard` call authenticates, and its owner: the client session
/// (session flow) or the entity and customer the backend will pay for (advanced flow).
public enum ThreeDSSavedCard {
    /// The oneWallet token `id` (a UUID), never its `value`.
    case session(walletTokenId: String, clientSessionId: String)
    /// The oneWallet token `id` (a UUID), never its `value`.
    case advanced(walletTokenId: String, entityId: String, customerReference: String)

    var subject: ThreeDSVersioningSubject {
        switch self {
        case let .session(walletTokenId, clientSessionId):
            return .savedCardSession(walletTokenId: walletTokenId, clientSessionId: clientSessionId)
        case let .advanced(walletTokenId, entityId, customerReference):
            return .savedCardAdvanced(
                walletTokenId: walletTokenId,
                entityId: entityId,
                customerReference: customerReference
            )
        }
    }
}

/// The versioning request body. `JSONEncoder` drops every `nil`, so each subject sends exactly
/// its own keys and nothing else — a mixed body is refused by the gateway.
struct ThreeDSVersioningRequest: Encodable {
    let deviceChannel = "APP"
    var tenantId: String?
    var formToken: String?
    var walletTokenId: String?
    var clientSessionId: String?
    var entityId: String?
    var customerReference: String?
    var networkToken: Bool?
    var amount: Int?
    var currency: String?

    enum CodingKeys: String, CodingKey {
        case deviceChannel = "device_channel"
        case tenantId = "tenant_id"
        case formToken = "form_token"
        case walletTokenId = "wallet_token_id"
        case clientSessionId = "client_session_id"
        case entityId = "entity_id"
        case customerReference = "customer_reference"
        case networkToken = "use_network_token"
        case amount
        case currency
    }

    init(
        subject: ThreeDSVersioningSubject,
        networkToken: Bool = false,
        amount: Int? = nil,
        currency: String? = nil
    ) {
        switch subject {
        case let .freshCard(tenantId, formToken):
            self.tenantId = tenantId
            self.formToken = formToken
        case let .savedCardSession(walletTokenId, clientSessionId):
            self.walletTokenId = walletTokenId
            self.clientSessionId = clientSessionId
        case let .savedCardAdvanced(walletTokenId, entityId, customerReference):
            self.walletTokenId = walletTokenId
            self.entityId = entityId
            self.customerReference = customerReference
        }
        // Absent, not `false`: the key only means something in network-token mode.
        self.networkToken = networkToken ? true : nil
        self.amount = amount
        self.currency = currency
    }
}

/// The app versioning answer. No 3DS Method fields: the device data was collected at init.
struct ThreeDSVersioningResponse: Decodable {
    let threeDSServerTransID: String
    let threeDSDirectoryServerID: String
    let threeDSProtocolVersion: String
    /// Network-token mode only: `false` means the FPAN fallback happened.
    let networkTokenUsed: Bool?

    enum CodingKeys: String, CodingKey {
        case threeDSServerTransID = "three_ds_server_trans_id"
        case threeDSDirectoryServerID = "three_ds_directory_server_id"
        case threeDSProtocolVersion = "three_ds_protocol_version"
        case networkTokenUsed = "network_token_used"
    }
}

/// An RFC 7807 answer. Branch on `type`, never on free text.
struct ThreeDSProblemResponse: Decodable {
    let type: String?
}

// MARK: - Challenge

/// The decoded `authentication.challenge_data` blob — base64url, unpadded, EMVCo camelCase.
///
/// The web keys (`acsURL`, `creq`, `challengeWindowSize`) are never present on a `01` blob; a
/// blob whose `deviceChannel` is not `01` is refused rather than guessed at.
struct ThreeDSChallengeBlob: Decodable {
    let deviceChannel: String
    let threeDSServerTransID: String
    let acsTransID: String
    let acsReferenceNumber: String
    let acsSignedContent: String

    static let appDeviceChannel = "01"

    /// - Throws: `ThreeDSError.invalidChallengeData` on anything that is not an app challenge blob.
    static func decode(_ challengeData: String) throws -> ThreeDSChallengeBlob {
        guard let data = base64URLDecode(challengeData),
              let blob = try? JSONDecoder().decode(ThreeDSChallengeBlob.self, from: data),
              blob.deviceChannel == appDeviceChannel else {
            throw ThreeDSError.invalidChallengeData
        }
        return blob
    }

    /// base64url, unpadded: `-`/`_` for `+`/`/`, and the `=` padding added back before decoding.
    static func base64URLDecode(_ string: String) -> Data? {
        var normalised = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalised.count % 4
        if remainder > 0 {
            normalised += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: normalised)
    }

    var challengeParameters: ThreeDSChallengeParameters {
        ThreeDSChallengeParameters(
            threeDSServerTransactionID: threeDSServerTransID,
            acsTransactionID: acsTransID,
            acsRefNumber: acsReferenceNumber,
            acsSignedContent: acsSignedContent
        )
    }
}

/// What `POST /v2/3ds/challenge-result` read back from the server once the challenge ended.
///
/// This — not the device-side callback — is the outcome. The merchant's truth is still
/// `GET /v2/payments/{id}` or the payment webhook: everything that transited the device is
/// untrusted.
public struct ThreeDSChallengeResult {
    public enum Outcome: String, Decodable {
        /// The results push ran and the authentication is terminal.
        case settled = "SETTLED"
        /// The push race was lost, or no push came. **A normal ending, not a spinner** — hand
        /// over to the merchant backend; nothing on the device polls Purse.
        case pending = "PENDING"
        /// No usable correlation (`UNKNOWN_TRANSACTION`, `NO_PAYMENT_BOUND`, `PAYMENT_NOT_FOUND`,
        /// `CORRELATION_UNAVAILABLE`, `RATE_LIMITED`). The payment still settles on its own.
        case rejected = "REJECTED"
    }

    public let result: Outcome
    public let paymentID: String?
    public let authenticationStatus: String?
    public let authorizationStatus: String?
    /// Set on `.rejected` only.
    public let reason: String?
    /// How the challenge ended on the device. Informational — never the payment outcome.
    public let challengeStatus: ThreeDSChallengeStatus
}

/// The wire shape of the challenge-result answer, which is always HTTP 200.
struct ThreeDSChallengeResultResponse: Decodable {
    /// A value this SDK does not know yet reads as `.pending` — "confirm server-side", the one
    /// answer that is always safe — rather than failing a 200 the server meant.
    let result: ThreeDSChallengeResult.Outcome
    let paymentID: String?
    let reason: String?
    let authentication: Status?
    let authorization: Status?

    struct Status: Decodable {
        let status: String?
    }

    enum CodingKeys: String, CodingKey {
        case result
        case paymentID = "payment_id"
        case reason
        case authentication
        case authorization
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .result)
        result = ThreeDSChallengeResult.Outcome(rawValue: raw) ?? .pending
        paymentID = try container.decodeIfPresent(String.self, forKey: .paymentID)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        authentication = try container.decodeIfPresent(Status.self, forKey: .authentication)
        authorization = try container.decodeIfPresent(Status.self, forKey: .authorization)
    }

    func asResult(challengeStatus: ThreeDSChallengeStatus) -> ThreeDSChallengeResult {
        ThreeDSChallengeResult(
            result: result,
            paymentID: paymentID,
            authenticationStatus: authentication?.status,
            authorizationStatus: authorization?.status,
            reason: reason,
            challengeStatus: challengeStatus
        )
    }
}

// MARK: - Results

/// What `submitSavedCard` resolves with: the `submit()` shape minus `vaultFormToken` and `card`.
public struct ThreeDSSavedCardResult {
    public let threeDSServerTransID: String
    public let sdk: ThreeDSSDKBlock
    /// Network-token mode only. `false` means versioning fell back to the FPAN and the payment
    /// is an ordinary saved-card one.
    public let networkTokenUsed: Bool?
}

// MARK: - Errors

/// Why the Purse 3DS chain could not run, or could not be trusted.
///
/// Surfaced inside `SecureFieldsError.threeDS(_:)`, so hosts keep one error channel.
public enum ThreeDSError: Error, Equatable {
    /// The `PurseSecureFields3DS` product is not linked: no 3DS SDK, no device data, no transaction.
    /// A configuration fault in the host app, not a cardholder-facing failure.
    case providerUnavailable
    /// `SecureFieldsConfig.appSDKConfiguration` is absent, unreadable, or carries no 3DS SDK
    /// API key — the entity has no Purse 3DS, or the host never passed the `data` its backend
    /// read from `GET /v2/entities/{entityId}/app-sdk-configuration`. A configuration fault in
    /// the host app, not a cardholder-facing failure.
    case configurationMissing
    /// `ThreeDS2Service.initialize(...)` failed, at init and again on the `submit()` retry.
    case initializationFailed(String)
    /// 422 `card-not-versionable`. On a **saved card** this is the "not eligible" answer — one
    /// answer for every cause — and the caller should show the card fields instead. Do not retry.
    case cardNotEligible
    /// 422 `not-configured`: the entity has no Purse 3DS, no Purse Vault tenant or no active
    /// wallet configuration. A configuration problem on Purse's side. Do not retry.
    case notConfigured
    /// Any other versioning refusal. `type` is the RFC 7807 `type`, absent on a body that
    /// carried none.
    case versioningFailed(statusCode: Int, type: String?)
    /// `POST /v2/3ds/challenge-result` was refused before it could answer — the endpoint itself
    /// always answers `200`, so this is the gateway: a `401` means `SecureFieldsConfig.apiKey` is
    /// missing or unknown. The payment is not affected; confirm it server-side.
    case challengeResultFailed(statusCode: Int, type: String?)
    /// A 3DS call to the Orchestration host never got a usable answer: network, timeout, or an
    /// unreadable body. Reported as a 3DS failure because the card may already be tokenized.
    case networkError
    /// `createTransaction` or `doChallenge` threw.
    case transactionFailed(String)
    /// The 3DS SDK's ephemeral public key was not a JWK object of strings.
    case invalidEphemeralKey
    /// The `challenge_data` blob was not base64url JSON, or was not a `deviceChannel: "01"` one.
    case invalidChallengeData
    /// `challenge()` was called with no live transaction — `submit()` / `submitSavedCard()` has
    /// not run, or the transaction was released.
    case noActiveTransaction
    /// `challenge()` was called while a challenge is already on screen. The first one goes on and
    /// answers its own completion.
    case challengeInProgress
}

/// The decoded `SecureFieldsConfig.appSDKConfiguration` — the `data` of
/// `GET /v2/entities/{entityId}/app-sdk-configuration`, base64 of a JSON document that may grow
/// without notice. Only what the 3DS chain needs is read; everything else is ignored.
struct AppSDKConfiguration {

    /// `three_ds.sdk_api_key`, or `nil` when there is nothing usable: no `data`, not base64, not
    /// JSON, no `three_ds` block (Purse 3DS is off on the entity) or a blank key.
    let threeDSAPIKey: String?

    init(data: String?) {
        struct Document: Decodable {
            struct ThreeDS: Decodable {
                let sdkAPIKey: String?
                enum CodingKeys: String, CodingKey { case sdkAPIKey = "sdk_api_key" }
            }
            let threeDS: ThreeDS?
            enum CodingKeys: String, CodingKey { case threeDS = "three_ds" }
        }
        // Standard base64 is what the endpoint sends; base64url and missing padding are
        // accepted too, so a backend that re-encodes it on the way is not read as "no 3DS".
        guard let data,
              let decoded = ThreeDSChallengeBlob.base64URLDecode(
                  data.filter { !$0.isWhitespace }.replacingOccurrences(of: "=", with: "")
              ),
              let document = try? JSONDecoder().decode(Document.self, from: decoded),
              let key = document.threeDS?.sdkAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty
        else {
            threeDSAPIKey = nil
            return
        }
        threeDSAPIKey = key
    }
}
