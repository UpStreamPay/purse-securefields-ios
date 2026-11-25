import Foundation
import Testing
import UIKit
@testable import PurseSecureFields

/// The Purse 3DS chain, with the Orchestration host stubbed at the URLSession seam and the
/// Netcetera SDK mocked behind `ThreeDSProvider` — the whole point of the provider being a
/// protocol: this package has no Netcetera dependency to mock around.
///
/// The provider is injected into each manager rather than installed through
/// `PurseThreeDS.register(_:)`, which is process-wide: a registered provider would reach every
/// manager built by the suites running in parallel.
@MainActor
struct ThreeDSTests {

    // MARK: - Fixtures

    private static func versioningBody(transID: String, extra: String = "") -> String {
        """
        {"three_ds_server_trans_id":"\(transID)","three_ds_directory_server_id":"A000000003",\
        "three_ds_protocol_version":"2.2.0"\(extra)}
        """
    }
    private static let tokenizeBody =
        #"{"form_token":"tok_3ds","card":{"bin":"492925","last_four_digits":"7956"}}"#
    private static let binBody =
        #"{"brands":[{"brand":"VISA","is_main":true,"pan_lengths":[16],"cvv_lengths":[3]}]}"#

    /// The app challenge blob of the guide: base64url, unpadded, EMVCo camelCase.
    private static func challengeBlob(
        transID: String,
        deviceChannel: String = "01"
    ) -> String {
        let json = """
        {"deviceChannel":"\(deviceChannel)","threeDSServerTransID":"\(transID)",\
        "acsTransID":"d8c1b3a2-acs","acsReferenceNumber":"3DS_LOA_ACS_201_13579",\
        "acsSignedContent":"signed-content"}
        """
        return Data(json.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private final class SpyDelegate: SecureFieldsDelegate {
        var tokenized: TokenizationResult?
        var failure: SecureFieldsError?
        func secureFieldsDidTokenize(_ result: TokenizationResult) { tokenized = result }
        func secureFieldsDidFail(_ error: SecureFieldsError) { failure = error }
        var brands: [CardBrand] = []
        func secureFieldsBrandsDetected(_ brands: [CardBrand]) { self.brands = brands }
        func secureFieldsFormValidityChanged(_ isValid: Bool) {}
    }


    private func makeManager(
        tenantId: String,
        provider: ThreeDSProvider?,
        fields: SecureFieldsFieldsConfig = .all,
        appSDKConfiguration: String? = validAppSDKConfiguration
    ) -> SecureFieldsManager {
        var config = SecureFieldsConfig(
            tenantId: tenantId,
            fields: fields,
            monitoringEnabled: false,
            appSDKConfiguration: appSDKConfiguration
        )
        config.urlSessionOverride = StubGatewayURLProtocol.makeSession()
        return SecureFieldsManager(config: config, isDebugHost: true, threeDSProvider: provider)
    }

    private func panField(_ m: SecureFieldsManager) -> SecurePANField {
        m.panContainer.subviews.compactMap { $0 as? SecurePANField }.first!
    }

    private func fillForm(_ m: SecureFieldsManager) {
        let pan = panField(m)
        pan.text = "4929251897047956"
        pan.textDidChange()
        let cvv = m.cvvView as! SecureCVVField
        cvv.text = "123"
        cvv.textDidChange()
        let exp = m.expDateView as! SecureExpDateField
        exp.text = "06/30"
        exp.textDidChange()
    }

    /// Routes every call of one test: the vault ones by tenant id, versioning by the tenant or
    /// wallet token id in its body, and challenge-result by the transaction id in its.
    ///
    /// The transaction id is per test — the suites run in parallel and a shared one would route
    /// another test's challenge-result answer here.
    private func stubGateway(
        tenantId: String,
        transID: String,
        versioning: StubGatewayURLProtocol.Stub? = nil,
        challengeResult: StubGatewayURLProtocol.Stub = .init(statusCode: 200, body: "{}")
    ) {
        let versioning = versioning ?? .init(statusCode: 200, body: Self.versioningBody(transID: transID))
        StubGatewayURLProtocol.register(tenantId: tenantId) { request, _ in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/bin-lookup") { return .init(statusCode: 200, body: Self.binBody) }
            if path.hasSuffix("/forms/secure-fields") { return .init(statusCode: 200, body: Self.tokenizeBody) }
            if path.hasSuffix("/3ds/versioning") { return versioning }
            return .init(statusCode: 404, body: "{}")
        }
        StubGatewayURLProtocol.register(tenantId: transID) { _, _ in challengeResult }
    }

    private func requests(_ tenantId: String, suffix: String) -> [(request: URLRequest, body: Data?)] {
        StubGatewayURLProtocol.requests(tenantId: tenantId)
            .filter { ($0.request.url?.path ?? "").hasSuffix(suffix) }
    }

    private func json(_ data: Data?) -> [String: Any] {
        guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    // MARK: - The sdk block

    @Test("the sdk block is snake_case and carries the ephemeral key as a JWK object")
    func sdkBlockShape() throws {
        let provider = MockThreeDSProvider()
        let block = try ThreeDSSDKBlock(parameters: provider.parameters)
        let encoded = try JSONEncoder().encode(block)
        let object = json(encoded)

        #expect(object["app_id"] as? String == "app-id")
        #expect(object["transaction_id"] as? String == "sdk-trans-id")
        #expect(object["reference_number"] as? String == "3DS_LOA_SDK_NCSA_020100_00123")
        #expect(object["encrypted_data"] as? String == "device-data-jwe")
        // An object, never the SDK's JSON string: a string there is a 400 on /sdk/ephemeral_public_key.
        let jwk = object["ephemeral_public_key"] as? [String: String]
        #expect(jwk?["kty"] == "EC")
        #expect(jwk?["crv"] == "P-256")
        #expect(jwk?["x"] == "x-value")
        // `getMessageVersion()` is not sent — the server holds the version it versioned with.
        #expect(object["message_version"] == nil)
        #expect(object.count == 5)
    }

    @Test("an ephemeral key that is not a JSON object is refused, not forwarded")
    func sdkBlockRefusesNonObjectKey() {
        let provider = MockThreeDSProvider()
        provider.parameters = ThreeDSAuthenticationRequestParameters(
            sdkAppID: "a", sdkTransactionID: "b", sdkReferenceNumber: "c",
            deviceData: "d", sdkEphemeralPublicKey: "not-json", messageVersion: "2.2.0"
        )
        #expect(throws: ThreeDSError.invalidEphemeralKey) {
            try ThreeDSSDKBlock(parameters: provider.parameters)
        }
    }

    // MARK: - submit()

    @Test("submit(threeDSEnabled:) versions with device_channel APP and returns the ids")
    func submitChainsVersioning() async throws {
        let tenantId = "tenant-3ds-submit"
        let provider = MockThreeDSProvider()
        stubGateway(tenantId: tenantId, transID: "trans-\(tenantId)")

        let manager = makeManager(tenantId: tenantId, provider: provider)
        let delegate = SpyDelegate()
        manager.delegate = delegate
        fillForm(manager)
        // Not just the fields: `submit()` also needs a brand, which only the BIN lookup answer
        // provides on a form with a PAN.
        try await waitUntil("the form to become submittable") {
            !delegate.brands.isEmpty && manager.isFieldValid(.pan)
                && manager.isFieldValid(.cvv) && manager.isFieldValid(.expDate)
        }

        manager.submit(threeDSEnabled: true)
        try await waitUntil("tokenization") { delegate.tokenized != nil || delegate.failure != nil }

        let result = try #require(delegate.tokenized)
        #expect(result.vaultFormToken == "tok_3ds")
        #expect(result.threeDSServerTransID == "trans-\(tenantId)")
        #expect(result.sdk?.appID == "app-id")

        let body = json(requests(tenantId, suffix: "/3ds/versioning").first?.body)
        // Absent means BROWSER server-side, and the answer would carry 3DS Method fields the app
        // cannot use.
        #expect(body["device_channel"] as? String == "APP")
        #expect(body["tenant_id"] as? String == tenantId)
        #expect(body["form_token"] as? String == "tok_3ds")
        #expect(body["use_network_token"] == nil)
        #expect(body.count == 3)

        // The two createTransaction arguments come from the versioning answer.
        #expect(provider.lastDirectoryServerID == "A000000003")
        #expect(provider.lastMessageVersion == "2.2.0")
    }

    @Test("submit() without threeDSEnabled never versions")
    func submitWithoutThreeDS() async throws {
        let tenantId = "tenant-3ds-off"
        let provider = MockThreeDSProvider()
        stubGateway(tenantId: tenantId, transID: "trans-\(tenantId)")

        let manager = makeManager(tenantId: tenantId, provider: provider)
        let delegate = SpyDelegate()
        manager.delegate = delegate
        fillForm(manager)
        // Not just the fields: `submit()` also needs a brand, which only the BIN lookup answer
        // provides on a form with a PAN.
        try await waitUntil("the form to become submittable") {
            !delegate.brands.isEmpty && manager.isFieldValid(.pan)
                && manager.isFieldValid(.cvv) && manager.isFieldValid(.expDate)
        }

        manager.submit()
        try await waitUntil("tokenization") { delegate.tokenized != nil }

        #expect(delegate.tokenized?.threeDSServerTransID == nil)
        #expect(delegate.tokenized?.sdk == nil)
        #expect(requests(tenantId, suffix: "/3ds/versioning").isEmpty)
    }

    @Test("a versioning failure keeps the fields so the card can be retried as typed")
    func versioningFailureKeepsFields() async throws {
        let tenantId = "tenant-3ds-422"
        let provider = MockThreeDSProvider()
        stubGateway(
            tenantId: tenantId,
            transID: "trans-\(tenantId)",
            versioning: .init(
                statusCode: 422,
                body: #"{"type":"urn:eu.purse:threeds:card-not-versionable"}"#
            )
        )

        let manager = makeManager(tenantId: tenantId, provider: provider)
        let delegate = SpyDelegate()
        manager.delegate = delegate
        fillForm(manager)
        // Not just the fields: `submit()` also needs a brand, which only the BIN lookup answer
        // provides on a form with a PAN.
        try await waitUntil("the form to become submittable") {
            !delegate.brands.isEmpty && manager.isFieldValid(.pan)
                && manager.isFieldValid(.cvv) && manager.isFieldValid(.expDate)
        }

        manager.submit(threeDSEnabled: true)
        try await waitUntil("failure") { delegate.failure != nil }

        guard case .threeDS(.cardNotEligible) = delegate.failure else {
            Issue.record("expected .threeDS(.cardNotEligible), got \(String(describing: delegate.failure))")
            return
        }
        #expect(delegate.tokenized == nil)
        // Not cleared: a failed attempt must be retryable without re-entering the card.
        #expect(manager.panDigitCount == 16)
        #expect(manager.hasFieldContent(.cvv))
    }

    @Test("submit(threeDSEnabled:) fails fast when the 3DS product is not linked")
    func noProviderFailsFast() async throws {
        let tenantId = "tenant-3ds-none"
        stubGateway(tenantId: tenantId, transID: "trans-\(tenantId)")

        let manager = makeManager(tenantId: tenantId, provider: nil)
        #expect(manager.isThreeDSAvailable == false)
        let delegate = SpyDelegate()
        manager.delegate = delegate
        fillForm(manager)
        // Not just the fields: `submit()` also needs a brand, which only the BIN lookup answer
        // provides on a form with a PAN.
        try await waitUntil("the form to become submittable") {
            !delegate.brands.isEmpty && manager.isFieldValid(.pan)
                && manager.isFieldValid(.cvv) && manager.isFieldValid(.expDate)
        }

        manager.submit(threeDSEnabled: true)
        try await waitUntil("failure") { delegate.failure != nil }

        guard case .threeDS(.providerUnavailable) = delegate.failure else {
            Issue.record("expected .threeDS(.providerUnavailable), got \(String(describing: delegate.failure))")
            return
        }
        #expect(requests(tenantId, suffix: "/3ds/versioning").isEmpty)
        // Fails *fast*: no vault token is minted that could never be paid.
        #expect(requests(tenantId, suffix: "/forms/secure-fields").isEmpty)
    }

    @Test("submit(threeDSEnabled:) fails fast when the host passed no app SDK configuration")
    func noConfigurationFailsFast() async throws {
        let tenantId = "tenant-3ds-noconf"
        stubGateway(tenantId: tenantId, transID: "trans-\(tenantId)")

        let provider = MockThreeDSProvider()
        let manager = makeManager(tenantId: tenantId, provider: provider, appSDKConfiguration: nil)
        #expect(manager.isThreeDSAvailable == false)
        let delegate = SpyDelegate()
        manager.delegate = delegate
        fillForm(manager)
        try await waitUntil("the form to become submittable") {
            !delegate.brands.isEmpty && manager.isFieldValid(.pan)
                && manager.isFieldValid(.cvv) && manager.isFieldValid(.expDate)
        }

        manager.submit(threeDSEnabled: true)
        try await waitUntil("failure") { delegate.failure != nil }

        guard case .threeDS(.configurationMissing) = delegate.failure else {
            Issue.record("expected .threeDS(.configurationMissing), got \(String(describing: delegate.failure))")
            return
        }
        // No key, so the 3DS SDK is never even asked — and nothing is tokenized.
        #expect(provider.initializeCount == 0)
        #expect(requests(tenantId, suffix: "/forms/secure-fields").isEmpty)
    }

    @Test("the 3DS SDK is initialized with the key of the app SDK configuration")
    func apiKeyReachesTheProvider() async throws {
        let provider = MockThreeDSProvider()
        let manager = makeManager(tenantId: "tenant-3ds-key", provider: provider)
        #expect(manager.isThreeDSAvailable)
        try await waitUntil("initialize") { provider.initializeCount > 0 }
        #expect(provider.lastAPIKey == sdkAPIKey)
        // The default environment is sandbox: non-production Directory Server roots apply.
        #expect(provider.lastProduction == false)
    }

    @Test(
        "an app SDK configuration with no usable key yields none",
        arguments: [
            nil,
            "",
            "not base64 !",
            encodedAppSDKConfiguration("not json"),
            encodedAppSDKConfiguration("{}"),
            encodedAppSDKConfiguration(#"{"three_ds":{"vendor":"NETCETERA"}}"#),
            encodedAppSDKConfiguration(#"{"three_ds":{"vendor":"NETCETERA","sdk_api_key":"  "}}"#),
        ] as [String?]
    )
    func unusableConfiguration(data: String?) {
        #expect(AppSDKConfiguration(data: data).threeDSAPIKey == nil)
    }

    @Test("a failed initialize is retried inside the submit chain")
    func initializeRetriedAtSubmit() async throws {
        let tenantId = "tenant-3ds-init"
        let provider = MockThreeDSProvider()
        provider.initializeResult = .failure(SecureFieldsError.invalidResponse)
        stubGateway(tenantId: tenantId, transID: "trans-\(tenantId)")

        let manager = makeManager(tenantId: tenantId, provider: provider)
        let delegate = SpyDelegate()
        manager.delegate = delegate
        fillForm(manager)
        // Not just the fields: `submit()` also needs a brand, which only the BIN lookup answer
        // provides on a form with a PAN.
        try await waitUntil("the form to become submittable") {
            !delegate.brands.isEmpty && manager.isFieldValid(.pan)
                && manager.isFieldValid(.cvv) && manager.isFieldValid(.expDate)
        }

        manager.submit(threeDSEnabled: true)
        try await waitUntil("first failure") { delegate.failure != nil }
        guard case .threeDS(.initializationFailed) = delegate.failure else {
            Issue.record("expected .threeDS(.initializationFailed), got \(String(describing: delegate.failure))")
            return
        }

        // The device is healthy again: the next submit re-runs initialize instead of staying failed.
        provider.initializeResult = .success(())
        delegate.failure = nil
        manager.submit(threeDSEnabled: true)
        try await waitUntil("second attempt") { delegate.tokenized != nil || delegate.failure != nil }
        #expect(delegate.tokenized?.threeDSServerTransID == "trans-\(tenantId)")
    }

    @Test("a CVV-only form never versions — the saved card it belongs to does")
    func cvvOnlySkipsVersioning() async throws {
        let tenantId = "tenant-3ds-cvvonly"
        let provider = MockThreeDSProvider()
        stubGateway(tenantId: tenantId, transID: "trans-\(tenantId)")

        let manager = makeManager(tenantId: tenantId, provider: provider, fields: .cvvOnly)
        let delegate = SpyDelegate()
        manager.delegate = delegate
        let cvv = manager.cvvView as! SecureCVVField
        cvv.text = "123"
        cvv.textDidChange()

        manager.submit(threeDSEnabled: true)
        try await waitUntil("tokenization") { delegate.tokenized != nil || delegate.failure != nil }

        #expect(delegate.tokenized?.threeDSServerTransID == nil)
        #expect(requests(tenantId, suffix: "/3ds/versioning").isEmpty)
    }

    // MARK: - Saved card

    @Test("submitSavedCard versions the session shape and tokenizes nothing")
    func savedCardSession() async throws {
        let walletTokenId = "wallet-token-session"
        let provider = MockThreeDSProvider()
        stubGateway(tenantId: walletTokenId, transID: "trans-\(walletTokenId)")

        let manager = makeManager(tenantId: "tenant-saved-session", provider: provider)
        var outcome: Result<ThreeDSSavedCardResult, SecureFieldsError>?
        manager.submitSavedCard(
            .session(walletTokenId: walletTokenId, clientSessionId: "session-42")
        ) { outcome = $0 }
        try await waitUntil("saved card") { outcome != nil }

        let result = try #require(try outcome?.get())
        #expect(result.threeDSServerTransID == "trans-\(walletTokenId)")
        #expect(result.networkTokenUsed == nil)

        let body = json(requests(walletTokenId, suffix: "/3ds/versioning").first?.body)
        #expect(body["device_channel"] as? String == "APP")
        #expect(body["wallet_token_id"] as? String == walletTokenId)
        #expect(body["client_session_id"] as? String == "session-42")
        // Never mixed with the fresh-card or advanced keys: the gateway refuses a mixed body.
        #expect(body.count == 3)
        #expect(requests(walletTokenId, suffix: "/forms/secure-fields").isEmpty)
    }

    @Test("network-token mode sends use_network_token, amount and currency, and reads it back")
    func savedCardNetworkToken() async throws {
        let walletTokenId = "wallet-token-nt"
        let provider = MockThreeDSProvider()
        stubGateway(
            tenantId: walletTokenId,
            transID: "trans-\(walletTokenId)",
            versioning: .init(
                statusCode: 200,
                body: """
                {"three_ds_server_trans_id":"trans-\(walletTokenId)","three_ds_directory_server_id":"A000000003",\
                "three_ds_protocol_version":"2.2.0","network_token_used":false}
                """
            )
        )

        let manager = makeManager(tenantId: "tenant-saved-nt", provider: provider)
        var outcome: Result<ThreeDSSavedCardResult, SecureFieldsError>?
        manager.submitSavedCard(
            .advanced(walletTokenId: walletTokenId, entityId: "entity-1", customerReference: "cust-42"),
            networkToken: true,
            amount: 11500,
            currency: "EUR"
        ) { outcome = $0 }
        try await waitUntil("saved card") { outcome != nil }

        // false: versioning fell back to the FPAN, the payment is an ordinary saved-card one.
        #expect(try outcome?.get().networkTokenUsed == false)

        let body = json(requests(walletTokenId, suffix: "/3ds/versioning").first?.body)
        #expect(body["use_network_token"] as? Bool == true)
        #expect(body["amount"] as? Int == 11500)
        #expect(body["currency"] as? String == "EUR")
        #expect(body["entity_id"] as? String == "entity-1")
        #expect(body["customer_reference"] as? String == "cust-42")
    }

    @Test("a saved card the gateway will not version surfaces as not eligible")
    func savedCardNotEligible() async throws {
        let walletTokenId = "wallet-token-ineligible"
        let provider = MockThreeDSProvider()
        stubGateway(
            tenantId: walletTokenId,
            transID: "trans-\(walletTokenId)",
            versioning: .init(
                statusCode: 422,
                body: #"{"type":"urn:eu.purse:threeds:card-not-versionable"}"#
            )
        )

        let manager = makeManager(tenantId: "tenant-saved-ineligible", provider: provider)
        var outcome: Result<ThreeDSSavedCardResult, SecureFieldsError>?
        manager.submitSavedCard(
            .session(walletTokenId: walletTokenId, clientSessionId: "session-1")
        ) { outcome = $0 }
        try await waitUntil("saved card") { outcome != nil }

        guard case .failure(.threeDS(.cardNotEligible)) = outcome else {
            Issue.record("expected .threeDS(.cardNotEligible), got \(String(describing: outcome))")
            return
        }
    }

    @Test("an entity without Purse 3DS is a distinct error from an ineligible card")
    func savedCardNotConfigured() async throws {
        let walletTokenId = "wallet-token-unconfigured"
        let provider = MockThreeDSProvider()
        stubGateway(
            tenantId: walletTokenId,
            transID: "trans-\(walletTokenId)",
            versioning: .init(statusCode: 422, body: #"{"type":"urn:eu.purse:threeds:not-configured"}"#)
        )

        let manager = makeManager(tenantId: "tenant-saved-unconfigured", provider: provider)
        var outcome: Result<ThreeDSSavedCardResult, SecureFieldsError>?
        manager.submitSavedCard(
            .session(walletTokenId: walletTokenId, clientSessionId: "session-1")
        ) { outcome = $0 }
        try await waitUntil("saved card") { outcome != nil }

        guard case .failure(.threeDS(.notConfigured)) = outcome else {
            Issue.record("expected .threeDS(.notConfigured), got \(String(describing: outcome))")
            return
        }
    }

    // MARK: - challenge()

    @Test("the challenge outcome is the server's, not the device callback's")
    func challengeReadsTheServer() async throws {
        let transID = "trans-wallet-token-challenge"
        let provider = MockThreeDSProvider()
        // The ACS said Y on the device — and the server is the one that decides.
        provider.challengeStatus = .completed(transStatus: "Y")

        let walletTokenId = "wallet-token-challenge"
        stubGateway(
            tenantId: walletTokenId,
            transID: transID,
            challengeResult: .init(
                statusCode: 200,
                body: """
                {"three_ds_server_trans_id":"\(transID)","payment_id":"pay-1","result":"PENDING",\
                "authentication":{"status":"IN_PROGRESS"},"authorization":{"status":"PENDING"}}
                """
            )
        )

        let manager = makeManager(tenantId: "tenant-challenge", provider: provider)
        var prepared: Result<ThreeDSSavedCardResult, SecureFieldsError>?
        manager.submitSavedCard(
            .session(walletTokenId: walletTokenId, clientSessionId: "session-1")
        ) { prepared = $0 }
        try await waitUntil("saved card") { prepared != nil }
        _ = try #require(try prepared?.get())

        var outcome: Result<ThreeDSChallengeResult, SecureFieldsError>?
        manager.challenge(Self.challengeBlob(transID: transID), presenting: UIViewController()) { outcome = $0 }
        try await waitUntil("challenge") { outcome != nil }

        let result = try #require(try outcome?.get())
        // PENDING is a normal ending, not a spinner.
        #expect(result.result == .pending)
        #expect(result.paymentID == "pay-1")
        #expect(result.authenticationStatus == "IN_PROGRESS")
        #expect(result.challengeStatus == .completed(transStatus: "Y"))

        let transaction = try #require(provider.createdTransactions.last)
        #expect(transaction.challengeParameters?.acsTransactionID == "d8c1b3a2-acs")
        #expect(transaction.challengeParameters?.acsRefNumber == "3DS_LOA_ACS_201_13579")
        // 5 minutes — the sdkMaxTimeout Purse announces to the ACS.
        #expect(transaction.timeoutMinutes == 5)
        // Released once the result is in, on every path.
        #expect(transaction.closeCount == 1)
        #expect(provider.cleanupCount >= 1)
    }

    @Test("a cancelled challenge still reads the result back")
    func cancelledChallengeStillReports() async throws {
        let transID = "trans-wallet-token-cancel"
        let provider = MockThreeDSProvider()
        provider.challengeStatus = .cancelled

        let walletTokenId = "wallet-token-cancel"
        stubGateway(
            tenantId: walletTokenId,
            transID: transID,
            challengeResult: .init(
                statusCode: 200,
                body: #"{"result":"REJECTED","reason":"NO_PAYMENT_BOUND"}"#
            )
        )

        let manager = makeManager(tenantId: "tenant-challenge-cancel", provider: provider)
        var prepared: Result<ThreeDSSavedCardResult, SecureFieldsError>?
        manager.submitSavedCard(
            .session(walletTokenId: walletTokenId, clientSessionId: "session-1")
        ) { prepared = $0 }
        try await waitUntil("saved card") { prepared != nil }

        var outcome: Result<ThreeDSChallengeResult, SecureFieldsError>?
        manager.challenge(Self.challengeBlob(transID: transID), presenting: UIViewController()) { outcome = $0 }
        try await waitUntil("challenge") { outcome != nil }

        let result = try #require(try outcome?.get())
        #expect(result.result == .rejected)
        #expect(result.reason == "NO_PAYMENT_BOUND")
        #expect(result.challengeStatus == .cancelled)
    }

    @Test("a challenge-result the gateway refuses is its own error, not a versioning one")
    func refusedChallengeResult() async throws {
        let transID = "trans-wallet-token-401"
        let provider = MockThreeDSProvider()
        let walletTokenId = "wallet-token-401"
        stubGateway(
            tenantId: walletTokenId,
            transID: transID,
            challengeResult: .init(statusCode: 401, body: #"{"code":"NO_API_CLIENT"}"#)
        )

        let manager = makeManager(tenantId: "tenant-challenge-401", provider: provider)
        var prepared: Result<ThreeDSSavedCardResult, SecureFieldsError>?
        manager.submitSavedCard(
            .session(walletTokenId: walletTokenId, clientSessionId: "session-1")
        ) { prepared = $0 }
        try await waitUntil("saved card") { prepared != nil }

        var outcome: Result<ThreeDSChallengeResult, SecureFieldsError>?
        manager.challenge(Self.challengeBlob(transID: transID), presenting: UIViewController()) { outcome = $0 }
        try await waitUntil("challenge") { outcome != nil }

        guard case .failure(.threeDS(.challengeResultFailed(statusCode: 401, _))) = outcome else {
            Issue.record("expected .challengeResultFailed(401), got \(String(describing: outcome))")
            return
        }
        // Released whatever the answer.
        #expect(provider.createdTransactions.last?.closeCount == 1)
    }

    @Test("a second challenge while one is on screen is refused, and the first still ends")
    func secondChallengeRefused() async throws {
        let transID = "trans-wallet-token-twice"
        let provider = MockThreeDSProvider()
        provider.holdChallenge = true
        let walletTokenId = "wallet-token-twice"
        stubGateway(
            tenantId: walletTokenId,
            transID: transID,
            challengeResult: .init(statusCode: 200, body: #"{"result":"SETTLED"}"#)
        )
        let manager = makeManager(tenantId: "tenant-challenge-twice", provider: provider)
        var prepared: Result<ThreeDSSavedCardResult, SecureFieldsError>?
        manager.submitSavedCard(.session(walletTokenId: walletTokenId, clientSessionId: "s")) { prepared = $0 }
        try await waitUntil("saved card") { prepared != nil }

        var first: Result<ThreeDSChallengeResult, SecureFieldsError>?
        var second: Result<ThreeDSChallengeResult, SecureFieldsError>?
        manager.challenge(Self.challengeBlob(transID: transID), presenting: UIViewController()) { first = $0 }
        manager.challenge(Self.challengeBlob(transID: transID), presenting: UIViewController()) { second = $0 }
        try await waitUntil("second refused") { second != nil }
        guard case .failure(.threeDS(.challengeInProgress)) = second else {
            Issue.record("expected .challengeInProgress, got \(String(describing: second))")
            return
        }
        // Nothing may close the challenge's transaction under it.
        manager.releaseThreeDS()
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(provider.createdTransactions.last?.closeCount == 0)

        provider.createdTransactions.last?.finishHeldChallenge()
        try await waitUntil("first ends") { first != nil }
        #expect((try? first?.get())?.result == .settled)
        #expect(provider.createdTransactions.last?.closeCount == 1)
    }

    @Test("a chain started during a challenge is refused, and a release elsewhere spares the service")
    func chainDuringChallengeRefused() async throws {
        let transID = "trans-wallet-token-during"
        let provider = MockThreeDSProvider()
        provider.holdChallenge = true
        let walletTokenId = "wallet-token-during"
        stubGateway(
            tenantId: walletTokenId,
            transID: transID,
            challengeResult: .init(statusCode: 200, body: #"{"result":"SETTLED"}"#)
        )
        let manager = makeManager(tenantId: "tenant-during", provider: provider)
        let other = makeManager(tenantId: "tenant-during-other", provider: provider)
        var prepared: Result<ThreeDSSavedCardResult, SecureFieldsError>?
        manager.submitSavedCard(.session(walletTokenId: walletTokenId, clientSessionId: "s")) { prepared = $0 }
        try await waitUntil("saved card") { prepared != nil }

        var challenged: Result<ThreeDSChallengeResult, SecureFieldsError>?
        manager.challenge(Self.challengeBlob(transID: transID), presenting: UIViewController()) { challenged = $0 }
        var second: Result<ThreeDSSavedCardResult, SecureFieldsError>?
        manager.submitSavedCard(.session(walletTokenId: walletTokenId, clientSessionId: "s")) { second = $0 }
        try await waitUntil("second chain refused") { second != nil }
        guard case .failure(.threeDS(.challengeInProgress)) = second else {
            Issue.record("expected .challengeInProgress, got \(String(describing: second))")
            return
        }
        // Another manager releasing the shared service must not clean it up under the challenge.
        let cleanupsBefore = provider.cleanupCount
        other.releaseThreeDS()
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(provider.cleanupCount == cleanupsBefore)

        provider.createdTransactions.last?.finishHeldChallenge()
        try await waitUntil("challenge ends") { challenged != nil }
        #expect(provider.cleanupCount == cleanupsBefore + 1)
    }

    @Test("the app SDK configuration is read whether padded, unpadded or base64url")
    func lenientConfigurationEncoding() {
        let json = #"{"three_ds":{"sdk_api_key":"key-1\n"},"x":"??>"}"#
        let standard = Data(json.utf8).base64EncodedString()
        let url = standard.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        let unpadded = standard.replacingOccurrences(of: "=", with: "")
        for variant in [standard, url, unpadded, " \(standard)\n"] {
            #expect(AppSDKConfiguration(data: variant).threeDSAPIKey == "key-1", "for \(variant)")
        }
    }

    @Test("a 3DS SDK that never answers initialize fails the chain instead of hanging it")
    func stalledInitializeTimesOut() async throws {
        let provider = MockThreeDSProvider()
        provider.holdInitialize = true
        let client = ThreeDSAPIClient(baseURL: "https://example.invalid", apiKey: nil, session: StubGatewayURLProtocol.makeSession())
        let coordinator = ThreeDSCoordinator(
            tenantId: "tenant-stall",
            client: client,
            provider: provider,
            apiKey: "key",
            isProduction: false,
            sdkTimeout: 0.2
        )
        var outcome: Result<ThreeDSCoordinator.Preparation, SecureFieldsError>?
        coordinator.prepare(formToken: "tok") { outcome = $0 }
        try await waitUntil("timeout") { outcome != nil }
        guard case .failure(.threeDS(.initializationFailed)) = outcome else {
            Issue.record("expected .initializationFailed, got \(String(describing: outcome))")
            return
        }
    }

    @Test("an initialize error never carries the 3DS SDK key")
    func initializeErrorIsRedacted() async throws {
        let provider = MockThreeDSProvider()
        provider.initializeResult = .failure(NSError(
            domain: "netcetera",
            code: 1037,
            userInfo: [NSLocalizedDescriptionKey: "invalid key \(sdkAPIKey)"]
        ))
        let manager = makeManager(tenantId: "tenant-redact", provider: provider)
        var outcome: Result<ThreeDSSavedCardResult, SecureFieldsError>?
        manager.submitSavedCard(.session(walletTokenId: "w-redact", clientSessionId: "s")) { outcome = $0 }
        try await waitUntil("failure") { outcome != nil }
        guard case .failure(.threeDS(.initializationFailed(let detail))) = outcome else {
            Issue.record("expected .initializationFailed, got \(String(describing: outcome))")
            return
        }
        #expect(!detail.contains(sdkAPIKey))
        #expect(detail.contains("<redacted>"))
    }

    @Test("challenge() reports a missing provider or configuration, not a missing transaction")
    func challengeReportsUnavailability() async throws {
        let manager = makeManager(tenantId: "tenant-challenge-noprovider", provider: nil)
        var outcome: Result<ThreeDSChallengeResult, SecureFieldsError>?
        manager.challenge(Self.challengeBlob(transID: "t"), presenting: UIViewController()) { outcome = $0 }
        try await waitUntil("failure") { outcome != nil }
        guard case .failure(.threeDS(.providerUnavailable)) = outcome else {
            Issue.record("expected .providerUnavailable, got \(String(describing: outcome))")
            return
        }
    }

    @Test("an unreadable versioning answer is a 3DS failure, not a tokenization one")
    func unreadableVersioningIsThreeDS() async throws {
        let walletTokenId = "wallet-token-garbled"
        stubGateway(
            tenantId: walletTokenId,
            transID: "trans-\(walletTokenId)",
            versioning: .init(statusCode: 200, body: "<html>gateway</html>")
        )
        let manager = makeManager(tenantId: "tenant-garbled", provider: MockThreeDSProvider())
        var outcome: Result<ThreeDSSavedCardResult, SecureFieldsError>?
        manager.submitSavedCard(.session(walletTokenId: walletTokenId, clientSessionId: "s")) { outcome = $0 }
        try await waitUntil("failure") { outcome != nil }
        guard case .failure(.threeDS(.networkError)) = outcome else {
            Issue.record("expected .threeDS(.networkError), got \(String(describing: outcome))")
            return
        }
    }

    @Test("an outcome this SDK does not know reads as pending, not as a failed call")
    func unknownOutcomeIsPending() throws {
        let decoded = try JSONDecoder().decode(
            ThreeDSChallengeResultResponse.self,
            from: Data(#"{"result":"SOMETHING_NEW"}"#.utf8)
        )
        #expect(decoded.result == .pending)
    }

    @Test("a blob that is not a deviceChannel 01 challenge is refused, not guessed at")
    func challengeRefusesBrowserBlob() async throws {
        let provider = MockThreeDSProvider()

        let walletTokenId = "wallet-token-blob"
        stubGateway(tenantId: walletTokenId, transID: "trans-\(walletTokenId)")

        let manager = makeManager(tenantId: "tenant-challenge-blob", provider: provider)
        var prepared: Result<ThreeDSSavedCardResult, SecureFieldsError>?
        manager.submitSavedCard(
            .session(walletTokenId: walletTokenId, clientSessionId: "session-1")
        ) { prepared = $0 }
        try await waitUntil("saved card") { prepared != nil }

        var outcome: Result<ThreeDSChallengeResult, SecureFieldsError>?
        manager.challenge(
            Self.challengeBlob(transID: "trans-\(walletTokenId)", deviceChannel: "02"),
            presenting: UIViewController()
        ) { outcome = $0 }
        try await waitUntil("challenge") { outcome != nil }

        guard case .failure(.threeDS(.invalidChallengeData)) = outcome else {
            Issue.record("expected .threeDS(.invalidChallengeData), got \(String(describing: outcome))")
            return
        }
    }

    @Test("challenge() without a live transaction is refused")
    func challengeWithoutTransaction() async throws {
        let provider = MockThreeDSProvider()

        let manager = makeManager(tenantId: "tenant-challenge-none", provider: provider)
        var outcome: Result<ThreeDSChallengeResult, SecureFieldsError>?
        manager.challenge(
            Self.challengeBlob(transID: "trans-never-prepared"),
            presenting: UIViewController()
        ) { outcome = $0 }
        try await waitUntil("challenge") { outcome != nil }

        guard case .failure(.threeDS(.noActiveTransaction)) = outcome else {
            Issue.record("expected .threeDS(.noActiveTransaction), got \(String(describing: outcome))")
            return
        }
    }

    @Test("releaseThreeDS closes the transaction left open by a frictionless verdict")
    func releaseOnFrictionlessPath() async throws {
        let provider = MockThreeDSProvider()

        let walletTokenId = "wallet-token-release"
        stubGateway(tenantId: walletTokenId, transID: "trans-\(walletTokenId)")

        let manager = makeManager(tenantId: "tenant-release", provider: provider)
        var prepared: Result<ThreeDSSavedCardResult, SecureFieldsError>?
        manager.submitSavedCard(
            .session(walletTokenId: walletTokenId, clientSessionId: "session-1")
        ) { prepared = $0 }
        try await waitUntil("saved card") { prepared != nil }

        let transaction = try #require(provider.createdTransactions.last)
        #expect(transaction.closeCount == 0)
        manager.releaseThreeDS()
        try await waitUntil("release") { transaction.closeCount == 1 }
        #expect(provider.cleanupCount >= 1)
    }

    // MARK: - The shared 3DS service

    @Test("one manager releasing the 3DS service does not break another")
    func releaseDoesNotBreakASecondManager() async throws {
        // `ThreeDS2Service` is process-wide: the `PurseSecureFields3DS` product hands the same one
        // to every manager. The demo's mode switch builds a second manager over the first.
        let provider = MockThreeDSProvider()
        let firstWallet = "wallet-token-shared-a"
        let secondWallet = "wallet-token-shared-b"
        stubGateway(tenantId: firstWallet, transID: "trans-\(firstWallet)")
        stubGateway(tenantId: secondWallet, transID: "trans-\(secondWallet)")

        let first = makeManager(tenantId: "tenant-shared-a", provider: provider)
        let second = makeManager(tenantId: "tenant-shared-b", provider: provider)

        var firstResult: Result<ThreeDSSavedCardResult, SecureFieldsError>?
        first.submitSavedCard(
            .session(walletTokenId: firstWallet, clientSessionId: "session-a")
        ) { firstResult = $0 }
        try await waitUntil("the first chain") { firstResult != nil }
        _ = try #require(try firstResult?.get())

        // The frictionless path: the first manager hands its verdict to the host and releases.
        first.releaseThreeDS()
        try await waitUntil("the service to be torn down") { !provider.isInitialized }

        var secondResult: Result<ThreeDSSavedCardResult, SecureFieldsError>?
        second.submitSavedCard(
            .session(walletTokenId: secondWallet, clientSessionId: "session-b")
        ) { secondResult = $0 }
        try await waitUntil("the second chain") { secondResult != nil }
        // Re-initialized instead of trusting a cached "ready".
        #expect(try secondResult?.get().threeDSServerTransID == "trans-\(secondWallet)")
    }

    @Test("a manager going away leaves the shared 3DS service alone")
    func deinitDoesNotCleanUpTheSharedService() async throws {
        let provider = MockThreeDSProvider()
        let wallet = "wallet-token-deinit"
        stubGateway(tenantId: wallet, transID: "trans-\(wallet)")

        do {
            let short = makeManager(tenantId: "tenant-deinit-short", provider: provider)
            var result: Result<ThreeDSSavedCardResult, SecureFieldsError>?
            short.submitSavedCard(
                .session(walletTokenId: wallet, clientSessionId: "session-1")
            ) { result = $0 }
            try await waitUntil("the chain") { result != nil }
            #expect(provider.createdTransactions.last?.closeCount == 0)
        }

        // Its own transaction is closed; `cleanup()` is not called on the shared service.
        try await waitUntil("the transaction to be closed") {
            provider.createdTransactions.last?.closeCount == 1
        }
        #expect(provider.cleanupCount == 0)
        #expect(provider.isInitialized)
    }

    // MARK: - Hosts

    @Test("with no PurseSecureFields3DS product linked, discovery finds nothing")
    func discoveryWithoutArtifact() {
        // Nothing registers a provider in this bundle, so this exercises the real lookup: the
        // open package alone has no `PurseSecureFields3DSProvider` class.
        PurseThreeDS.resetDiscovery()
        #expect(PurseThreeDS.provider == nil)
    }

    @Test("the gateway api key travels in a header, and only when the host set one")
    func apiKeyHeader() async throws {
        let provider = MockThreeDSProvider()
        let wallet = "wallet-token-apikey"
        stubGateway(tenantId: wallet, transID: "trans-\(wallet)")

        var config = SecureFieldsConfig(
            tenantId: "tenant-apikey",
            apiKey: "key-1",
            monitoringEnabled: false,
            appSDKConfiguration: validAppSDKConfiguration
        )
        config.urlSessionOverride = StubGatewayURLProtocol.makeSession()
        let manager = SecureFieldsManager(config: config, isDebugHost: true, threeDSProvider: provider)

        var result: Result<ThreeDSSavedCardResult, SecureFieldsError>?
        manager.submitSavedCard(.session(walletTokenId: wallet, clientSessionId: "s")) { result = $0 }
        try await waitUntil("the chain") { result != nil }

        let versioning = try #require(requests(wallet, suffix: "/3ds/versioning").first?.request)
        // A header, never the URL: a URL is written to proxy and access logs (SDK-12426).
        #expect(versioning.value(forHTTPHeaderField: "X-Api-Key") == "key-1")
        #expect(versioning.url?.query == nil)
    }

    @Test("versioning and challenge-result go to the Orchestration host, not the Vault one")
    func orchestrationHost() {
        #expect(VaultEnvironment.test.orchestrationApiRoot == "https://api.purse-test.com/payment/v2")
        #expect(VaultEnvironment.sandbox.orchestrationApiRoot == "https://api.purse-sandbox.com/payment/v2")
        #expect(VaultEnvironment.production.orchestrationApiRoot == "https://api.purse-live.com/payment/v2")
        #expect(VaultEnvironment.production.apiRoot == "https://api.vault.purse-secure.com")
    }
}

/// The `data` of `GET /v2/entities/{entityId}/app-sdk-configuration`: base64 of a JSON document.
/// File-level, not on the suite: a parameterized `@Test`'s arguments are evaluated outside its
/// actor.
private func encodedAppSDKConfiguration(_ json: String) -> String {
    Data(json.utf8).base64EncodedString()
}
private let sdkAPIKey = "11111111-2222-4333-8444-555555555555"
/// Carries a field the SDK does not know: the document may grow without notice.
private let validAppSDKConfiguration = encodedAppSDKConfiguration(
    #"{"three_ds":{"vendor":"NETCETERA","sdk_api_key":"\#(sdkAPIKey)"},"later_addition":{"x":1}}"#
)
