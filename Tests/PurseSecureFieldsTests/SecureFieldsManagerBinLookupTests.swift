import Foundation
import Testing
import UIKit
@testable import PurseSecureFields

/// BIN-lookup re-query behaviour: the lookup must follow the PAN as it
/// grows, or a BIN that only becomes discriminant past 8 digits is undetectable — the card
/// below answers `brands: []` on its first 8-10 digits and MASTERCARD from the 11th.
@MainActor
struct SecureFieldsManagerBinLookupTests {

    private final class SpyDelegate: SecureFieldsDelegate {
        var brandEvents: [[CardBrand]] = []
        func secureFieldsDidTokenize(_ result: TokenizationResult) {}
        func secureFieldsDidFail(_ error: SecureFieldsError) {}
        func secureFieldsBrandsDetected(_ brands: [CardBrand]) { brandEvents.append(brands) }
        func secureFieldsFormValidityChanged(_ isValid: Bool) {}
    }

    /// Answers like the real gateway for `2303770003322342`: nothing until 11 digits.
    private static func lateBinBody(forPrefix prefix: String) -> String {
        prefix.count >= 11
            ? #"{"brands":[{"brand":"MASTERCARD","is_main":true,"pan_lengths":[16],"cvv_lengths":[3]}]}"#
            : #"{"brands":[]}"#
    }

    private static func sentPrefixes(tenantId: String) -> [String] {
        StubGatewayURLProtocol.requests(tenantId: tenantId)
            .filter { $0.request.url!.path.hasSuffix("/bin-lookup") }
            .compactMap { call in
                guard let body = call.body,
                      let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
                else { return nil }
                return json["first_digits"] as? String
            }
    }

    private func makeManager(tenantId: String) -> SecureFieldsManager {
        var config = SecureFieldsConfig(
            tenantId: tenantId,
            brands: [.mastercard, .visa],
            monitoringEnabled: false
        )
        config.urlSessionOverride = StubGatewayURLProtocol.makeSession()
        return SecureFieldsManager(config: config)
    }

    private func panField(_ m: SecureFieldsManager) -> SecurePANField {
        m.panContainer.subviews.compactMap { $0 as? SecurePANField }.first!
    }

    /// Types one digit, then waits for whatever lookup it triggered to land. A digit whose
    /// prefix was already queried fires nothing, so the wait for a new request is bounded and
    /// its expiry is not a failure.
    private func typeDigit(_ c: Character, into field: SecurePANField, tenantId: String) async throws {
        let before = Self.sentPrefixes(tenantId: tenantId).count
        field.text = (field.storedText ?? "") + String(c)
        field.textDidChange()

        // 300 ms debounce, plus room for the request to be recorded on a loaded machine.
        let deadline = Date().addingTimeInterval(2)
        while Self.sentPrefixes(tenantId: tenantId).count == before, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        // The stub answers synchronously; one more turn lets the response reach the main queue
        // and apply its brand state.
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    @Test func brandIsDetectedWhenTheBinOnlyResolvesPastEightDigits() async throws {
        let tenantId = "late-\(UUID().uuidString)"
        StubGatewayURLProtocol.register(tenantId: tenantId) { _, body in
            guard let body,
                  let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let prefix = json["first_digits"] as? String
            else { return .init(statusCode: 200, body: #"{"brands":[]}"#) }
            return .init(statusCode: 200, body: Self.lateBinBody(forPrefix: prefix))
        }
        let manager = makeManager(tenantId: tenantId)
        let delegate = SpyDelegate()
        manager.delegate = delegate
        let pan = panField(manager)

        for c in "23037700" { try await typeDigit(c, into: pan, tenantId: tenantId) }
        #expect(delegate.brandEvents.last ?? [] == [], "8 digits: the API knows nothing yet")

        for c in "003" { try await typeDigit(c, into: pan, tenantId: tenantId) }   // 9th, 10th, 11th digit

        #expect(delegate.brandEvents.last == [.mastercard], "11 digits must resolve the brand")
        #expect(Self.sentPrefixes(tenantId: tenantId).contains("23037700003"))
    }

    @Test func prefixStopsGrowingAtElevenDigits() async throws {
        let tenantId = "dedupe-\(UUID().uuidString)"
        StubGatewayURLProtocol.register(tenantId: tenantId) { _, _ in
            .init(statusCode: 200, body: #"{"brands":[{"brand":"VISA","is_main":true,"pan_lengths":[16],"cvv_lengths":[3]}]}"#)
        }
        let manager = makeManager(tenantId: tenantId)
        let pan = panField(manager)

        for c in "4111111111111111" { try await typeDigit(c, into: pan, tenantId: tenantId) }   // 16 digits

        let prefixes = Self.sentPrefixes(tenantId: tenantId)
        // One request per distinct prefix: 8 through 11 digits, then nothing — digits 12-16
        // would all produce the same 11-digit body.
        #expect(prefixes.map(\.count) == [8, 9, 10, 11])
        #expect(Set(prefixes).count == prefixes.count, "no prefix queried twice")
    }

    @Test func lookupsStopAndBrandsClearBelowEightDigits() async throws {
        let tenantId = "clear-\(UUID().uuidString)"
        StubGatewayURLProtocol.register(tenantId: tenantId) { _, _ in
            .init(statusCode: 200, body: #"{"brands":[{"brand":"VISA","is_main":true,"pan_lengths":[16],"cvv_lengths":[3]}]}"#)
        }
        let manager = makeManager(tenantId: tenantId)
        let delegate = SpyDelegate()
        manager.delegate = delegate
        let pan = panField(manager)

        for c in "41111111" { try await typeDigit(c, into: pan, tenantId: tenantId) }
        #expect(delegate.brandEvents.last == [.visa])

        pan.text = "4111"
        pan.textDidChange()
        try await Task.sleep(nanoseconds: 500_000_000)

        #expect(delegate.brandEvents.last == [], "dropping below 8 digits clears the brands")
    }
}
