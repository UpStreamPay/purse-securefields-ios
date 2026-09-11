import Foundation
import Testing
import UIKit
@testable import PurseSecureFields

/// End-to-end Oney submit through the real manager, with the gateway stubbed at the URLSession
/// seam — the scenario that failed with `API_ERROR 400` in production (SDK-12108, gap 19):
/// BIN lookup detects ONEY, the CVV field switches to birthdate mode, and the tokenize request
/// must carry neither `cvv` nor any birthdate key.
@MainActor
struct SecureFieldsManagerSubmitTests {

    private final class SpyDelegate: SecureFieldsDelegate {
        var tokenized: TokenizationResult?
        var failure: SecureFieldsError?
        func secureFieldsDidTokenize(_ result: TokenizationResult) { tokenized = result }
        func secureFieldsDidFail(_ error: SecureFieldsError) { failure = error }
        var brands: [CardBrand] = []
        func secureFieldsBrandsDetected(_ brands: [CardBrand]) { self.brands = brands }
        func secureFieldsFormValidityChanged(_ isValid: Bool) {}
    }

    private static let oneyBinBody =
        #"{"brands":[{"brand":"ONEY","is_main":true,"pan_lengths":[19],"cvv_lengths":[3]}]}"#
    private static let tokenizeSuccessBody =
        #"{"form_token":"tok_oney","card":{"bin":"50320260","last_four_digits":"2327"}}"#

    private func makeManager(
        tenantId: String,
        brands: [CardBrand],
        fields: SecureFieldsFieldsConfig = .all
    ) -> SecureFieldsManager {
        var config = SecureFieldsConfig(tenantId: tenantId, brands: brands, fields: fields, monitoringEnabled: false)
        config.urlSessionOverride = StubGatewayURLProtocol.makeSession()
        return SecureFieldsManager(config: config)
    }

    private func type(_ value: String, into field: SecureBaseField) {
        field.text = value
        field.textDidChange()
    }

    private func panField(_ m: SecureFieldsManager) -> SecurePANField {
        m.panContainer.subviews.compactMap { $0 as? SecurePANField }.first!
    }
    private func cvvField(_ m: SecureFieldsManager) -> SecureCVVField { m.cvvView as! SecureCVVField }
    private func expField(_ m: SecureFieldsManager) -> SecureExpDateField { m.expDateView as! SecureExpDateField }

    /// Polls until `condition` holds, instead of sleeping a fixed amount: BIN lookup and submit
    /// hop main → URLSession → main, and a fixed wait turns into a flake as soon as the machine
    /// is loaded (swift-testing runs these suites in parallel).
    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 10,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(condition(), "timed out waiting for \(description)")
    }

    @Test func oneySubmitSendsNoCvvAndNoBirthdate() async throws {
        let tenantId = "oney-\(UUID().uuidString)"
        StubGatewayURLProtocol.register(tenantId: tenantId) { request, _ in
            request.url!.path.hasSuffix("/bin-lookup")
                ? .init(statusCode: 200, body: Self.oneyBinBody)
                : .init(statusCode: 200, body: Self.tokenizeSuccessBody)
        }
        let manager = makeManager(tenantId: tenantId, brands: [.oney])
        let delegate = SpyDelegate()
        manager.delegate = delegate

        type("5032026098999722327", into: panField(manager))
        // 300 ms BIN-lookup debounce, then the stubbed response lands on the main queue.
        try await waitUntil("the Oney brand to be applied") { cvvField(manager).inputMode == .birthdate }

        #expect(cvvField(manager).inputMode == .birthdate)
        #expect(manager.isFieldValid(.pan), "19-digit Oney PAN must validate")

        // The date picker path is private; set the picked value the way SecureCVVFieldTests does.
        cvvField(manager).text = "1990-01-01"
        cvvField(manager).setValidity(true)
        type("1230", into: expField(manager))

        manager.submit()
        try await waitUntil("tokenization to complete") { delegate.tokenized != nil || delegate.failure != nil }

        #expect(delegate.failure == nil)
        #expect(delegate.tokenized?.vaultFormToken == "tok_oney")
        // The date is never sent nor echoed — the result is the only place it can be read back.
        #expect(delegate.tokenized?.birthDate == "1990-01-01")
        #expect(delegate.tokenized?.selectedNetwork == .oney)

        let tokenizeCall = StubGatewayURLProtocol.requests(tenantId: tenantId)
            .first { $0.request.url!.path.hasSuffix("/forms/secure-fields") }
        let body = try #require(tokenizeCall?.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(json["cvv"] == nil, "birthdate mode must omit cvv")
        #expect(json["birth_date"] == nil, "the birthdate must never go on the wire")
        let card = try #require(json["card"] as? [String: Any])
        #expect(card["pan"] as? String == "5032026098999722327")
        #expect(card["selected_network"] as? String == "ONEY")
    }

    @Test func regularSubmitSendsCvv() async throws {
        let tenantId = "visa-\(UUID().uuidString)"
        StubGatewayURLProtocol.register(tenantId: tenantId) { request, _ in
            request.url!.path.hasSuffix("/bin-lookup")
                ? .init(statusCode: 200, body: #"{"brands":[{"brand":"VISA","is_main":true,"pan_lengths":[16],"cvv_lengths":[3]}]}"#)
                : .init(statusCode: 200, body: #"{"form_token":"tok_visa","card":{"bin":"41111111","last_four_digits":"1111"}}"#)
        }
        let manager = makeManager(tenantId: tenantId, brands: [.visa])
        let delegate = SpyDelegate()
        manager.delegate = delegate

        type("4111111111111111", into: panField(manager))
        try await waitUntil("the VISA brand to be detected") { !delegate.brands.isEmpty }

        #expect(cvvField(manager).inputMode == .cvv)
        type("123", into: cvvField(manager))
        type("1230", into: expField(manager))

        manager.submit()
        try await waitUntil("tokenization to complete") { delegate.tokenized != nil || delegate.failure != nil }

        #expect(delegate.tokenized?.vaultFormToken == "tok_visa")
        #expect(delegate.tokenized?.birthDate == nil)
        #expect(delegate.tokenized?.selectedNetwork == .visa)

        let tokenizeCall = StubGatewayURLProtocol.requests(tenantId: tenantId)
            .first { $0.request.url!.path.hasSuffix("/forms/secure-fields") }
        let body = try #require(tokenizeCall?.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(json["cvv"] as? String == "123")
        #expect(json["birth_date"] == nil)
    }

    /// With the selector disabled (the default), the merchant names the network of a co-badged
    /// card through `submit(selectedNetwork:)` — SDK-12108, gap 11.
    @Test func submitOverridesTheSelectedNetworkOnACobadgedCard() async throws {
        let tenantId = "cobadge-\(UUID().uuidString)"
        StubGatewayURLProtocol.register(tenantId: tenantId) { request, _ in
            request.url!.path.hasSuffix("/bin-lookup")
                ? .init(statusCode: 200, body: #"""
                    {"brands":[{"brand":"CARTE_BANCAIRE","is_main":true,"pan_lengths":[16],"cvv_lengths":[3]},
                               {"brand":"VISA","is_main":false,"pan_lengths":[16],"cvv_lengths":[3]}]}
                    """#)
                : .init(statusCode: 200, body: #"{"form_token":"tok_cb","card":{"bin":"41111111","last_four_digits":"1111"}}"#)
        }
        let manager = makeManager(tenantId: tenantId, brands: [.carteBancaire, .visa])
        let delegate = SpyDelegate()
        manager.delegate = delegate

        type("4111111111111111", into: panField(manager))
        try await waitUntil("both brands to be detected") { delegate.brands.count == 2 }
        type("123", into: cvvField(manager))
        type("1230", into: expField(manager))

        // Config order makes Cartes Bancaires the resolved default; the merchant asks for Visa.
        manager.submit(selectedNetwork: .visa)
        try await waitUntil("tokenization to complete") { delegate.tokenized != nil || delegate.failure != nil }

        let tokenizeCall = StubGatewayURLProtocol.requests(tenantId: tenantId)
            .first { $0.request.url!.path.hasSuffix("/forms/secure-fields") }
        let body = try #require(tokenizeCall?.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let card = try #require(json["card"] as? [String: Any])

        #expect(card["selected_network"] as? String == "VISA")
        #expect(delegate.tokenized?.selectedNetwork == .visa)
    }

    // MARK: CVV-only (SDK-12287)

    /// The CVV-only form end to end: no BIN lookup is ever sent, the tokenize body is exactly
    /// `{"cvv": "…"}`, and the card-less response reaches the host with `bin`, `lastFourDigits`
    /// and `selectedNetwork` all nil. `selectedNetwork`/`saveToken` passed to `submit` are ignored
    /// — a `card` holding only `selected_network` is rejected by the gateway for its missing expiry.
    @Test func cvvOnlySubmitSendsTheCvvAlone() async throws {
        let tenantId = "cvvonly-\(UUID().uuidString)"
        StubGatewayURLProtocol.register(tenantId: tenantId) { _, _ in
            .init(statusCode: 200, body: #"{"form_token":"tok_cvv"}"#)
        }
        let manager = makeManager(tenantId: tenantId, brands: [.visa, .amex], fields: .cvvOnly)
        let delegate = SpyDelegate()
        manager.delegate = delegate

        type("1234", into: cvvField(manager))
        #expect(manager.isFieldValid(.cvv), "4 digits must validate while no brand is known")

        manager.submit(selectedNetwork: .visa, saveToken: true)
        try await waitUntil("tokenization to complete") { delegate.tokenized != nil || delegate.failure != nil }

        #expect(delegate.failure == nil)
        let result = try #require(delegate.tokenized)
        #expect(result.vaultFormToken == "tok_cvv")
        #expect(result.bin == nil)
        #expect(result.lastFourDigits == nil)
        #expect(result.selectedNetwork == nil)
        #expect(result.detectedBrands.isEmpty)
        #expect(result.birthDate == nil)

        let calls = StubGatewayURLProtocol.requests(tenantId: tenantId)
        #expect(calls.allSatisfy { !$0.request.url!.path.hasSuffix("/bin-lookup") }, "no PAN field, no BIN lookup")
        let tokenizeCall = try #require(calls.first { $0.request.url!.path.hasSuffix("/forms/secure-fields") })
        let body = try #require(tokenizeCall.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["cvv"] as? String == "1234")
        #expect(json["card"] == nil, "a CVV-only request must not carry `card`, not even empty")
        #expect(json.count == 1)

        // Fields are zeroed at submit and brand state reset on success, as for a full form.
        #expect(manager.hasFieldContent(.cvv) == false)
        #expect(manager.expectedLengths(for: .cvv) == [3, 4])
    }

    @Test func cvvOnlyThreeDigitsAlsoSubmits() async throws {
        let tenantId = "cvvonly3-\(UUID().uuidString)"
        StubGatewayURLProtocol.register(tenantId: tenantId) { _, _ in
            .init(statusCode: 200, body: #"{"form_token":"tok_cvv3"}"#)
        }
        let manager = makeManager(tenantId: tenantId, brands: [.visa], fields: .cvvOnly)
        let delegate = SpyDelegate()
        manager.delegate = delegate

        type("123", into: cvvField(manager))
        manager.submit()
        try await waitUntil("tokenization to complete") { delegate.tokenized != nil || delegate.failure != nil }

        #expect(delegate.tokenized?.vaultFormToken == "tok_cvv3")
    }

    /// On a full form `selectBrand` is a programmatic chip tap: it changes the network submitted
    /// for a co-badged card even with the selector hidden (mirrors Android's `setBrandSelection`).
    @Test func fullFormSelectBrandDrivesTheSubmittedNetwork() async throws {
        let tenantId = "select-\(UUID().uuidString)"
        StubGatewayURLProtocol.register(tenantId: tenantId) { request, _ in
            request.url!.path.hasSuffix("/bin-lookup")
                ? .init(statusCode: 200, body: #"""
                    {"brands":[{"brand":"CARTE_BANCAIRE","is_main":true,"pan_lengths":[16],"cvv_lengths":[3]},
                               {"brand":"VISA","is_main":false,"pan_lengths":[16],"cvv_lengths":[3]}]}
                    """#)
                : .init(statusCode: 200, body: #"{"form_token":"tok_sel","card":{"bin":"41111111","last_four_digits":"1111"}}"#)
        }
        let manager = makeManager(tenantId: tenantId, brands: [.carteBancaire, .visa])
        let delegate = SpyDelegate()
        manager.delegate = delegate

        type("4111111111111111", into: panField(manager))
        try await waitUntil("both brands to be detected") { delegate.brands.count == 2 }
        #expect(manager.selectedBrand == .carteBancaire, "config order pre-selects CB")

        manager.selectBrand(.visa)
        #expect(manager.selectedBrand == .visa)

        type("123", into: cvvField(manager))
        type("1230", into: expField(manager))
        manager.submit()
        try await waitUntil("tokenization to complete") { delegate.tokenized != nil || delegate.failure != nil }

        let tokenizeCall = StubGatewayURLProtocol.requests(tenantId: tenantId)
            .first { $0.request.url!.path.hasSuffix("/forms/secure-fields") }
        let body = try #require(tokenizeCall?.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let card = try #require(json["card"] as? [String: Any])
        #expect(card["selected_network"] as? String == "VISA")
        #expect(delegate.tokenized?.selectedNetwork == .visa)
    }

    /// A full form still decodes the card block — the optional response field must not regress it.
    @Test func fullFormResultCarriesTheCard() async throws {
        let tenantId = "full-\(UUID().uuidString)"
        StubGatewayURLProtocol.register(tenantId: tenantId) { request, _ in
            request.url!.path.hasSuffix("/bin-lookup")
                ? .init(statusCode: 200, body: #"{"brands":[{"brand":"VISA","is_main":true,"pan_lengths":[16],"cvv_lengths":[3]}]}"#)
                : .init(statusCode: 200, body: #"{"form_token":"tok_visa","card":{"bin":"41111111","last_four_digits":"1111"}}"#)
        }
        let manager = makeManager(tenantId: tenantId, brands: [.visa])
        let delegate = SpyDelegate()
        manager.delegate = delegate

        type("4111111111111111", into: panField(manager))
        try await waitUntil("the VISA brand to be detected") { !delegate.brands.isEmpty }
        type("123", into: cvvField(manager))
        type("1230", into: expField(manager))
        manager.submit()
        try await waitUntil("tokenization to complete") { delegate.tokenized != nil || delegate.failure != nil }

        #expect(delegate.tokenized?.bin == "41111111")
        #expect(delegate.tokenized?.lastFourDigits == "1111")
    }
}
