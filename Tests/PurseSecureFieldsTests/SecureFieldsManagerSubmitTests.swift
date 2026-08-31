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
        func secureFieldsBrandsDetected(_ brands: [CardBrand]) {}
        func secureFieldsFormValidityChanged(_ isValid: Bool) {}
    }

    private static let oneyBinBody =
        #"{"brands":[{"brand":"ONEY","is_main":true,"pan_lengths":[19],"cvv_lengths":[3]}]}"#
    private static let tokenizeSuccessBody =
        #"{"form_token":"tok_oney","card":{"bin":"50320260","last_four_digits":"2327"}}"#

    private func makeManager(tenantId: String, brands: [CardBrand]) -> SecureFieldsManager {
        var config = SecureFieldsConfig(tenantId: tenantId, brands: brands, monitoringEnabled: false)
        config.testURLSession = StubGatewayURLProtocol.makeSession()
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
        try await Task.sleep(nanoseconds: 1_200_000_000)

        #expect(cvvField(manager).inputMode == .birthdate)
        #expect(manager.isFieldValid(.pan), "19-digit Oney PAN must validate")

        // The date picker path is private; set the picked value the way SecureCVVFieldTests does.
        cvvField(manager).text = "1990-01-01"
        cvvField(manager).setValidity(true)
        type("1230", into: expField(manager))

        manager.submit()
        try await Task.sleep(nanoseconds: 1_000_000_000)

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
        try await Task.sleep(nanoseconds: 1_200_000_000)

        #expect(cvvField(manager).inputMode == .cvv)
        type("123", into: cvvField(manager))
        type("1230", into: expField(manager))

        manager.submit()
        try await Task.sleep(nanoseconds: 1_000_000_000)

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
}
