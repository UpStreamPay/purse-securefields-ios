#if DEBUG
import Foundation
import PurseSecureFields

/// Builds `SecureFieldsManager` instances wired to `MockURLProtocol` for the bug gallery, and
/// builds the small BIN-lookup / tokenization JSON fixtures each screen needs. Kept separate from
/// `MockURLProtocol` itself (which stays generic infrastructure reused by `DemoViewController`
/// and `DemoUITests`).
enum BugSecureFieldsFactory {
    static func make(
        brands: [CardBrand] = CardBrand.allCases,
        tenantId: String = "bug-gallery"
    ) -> SecureFieldsManager {
        var config = SecureFieldsConfig(
            tenantId: tenantId,
            environment: .test,
            brands: brands,
            placeholders: SecureFieldsPlaceholders(
                pan: "Numéro de carte",
                cvv: "CVV",
                expDate: "MM/AA",
                holderName: "Nom du porteur"
            )
        )
        config.testURLSession = MockURLProtocol.makeSession()
        return SecureFieldsManager(config: config)
    }
}

/// A single brand entry for a mocked BIN-lookup response.
struct MockBinBrand {
    let brand: CardBrand
    let isMain: Bool
    let panLengths: [Int]
    let cvvLengths: [Int]

    init(_ brand: CardBrand, isMain: Bool, panLengths: [Int], cvvLengths: [Int] = [3]) {
        self.brand = brand
        self.isMain = isMain
        self.panLengths = panLengths
        self.cvvLengths = cvvLengths
    }
}

enum MockScenarios {

    /// Clears every mock handler / captured request — call this from each screen's `viewDidLoad`
    /// so unrelated bug screens (which share the same process-wide `MockURLProtocol.handlers`
    /// dictionary) never leak state into one another.
    static func reset() {
        MockURLProtocol.handlers = [:]
        MockURLProtocol.capturedBodies = [:]
        MockURLProtocol.onRequest = nil
    }

    static func setBinLookup(_ brands: [MockBinBrand], statusCode: Int = 200) {
        let brandsJSON = brands.map { b -> String in
            let pan = b.panLengths.map(String.init).joined(separator: ",")
            let cvv = b.cvvLengths.map(String.init).joined(separator: ",")
            return #"{"brand":"\#(b.brand.rawValue)","is_main":\#(b.isMain),"pan_lengths":[\#(pan)],"cvv_lengths":[\#(cvv)]}"#
        }.joined(separator: ",")
        let json = #"{"brands":[\#(brandsJSON)]}"#
        MockURLProtocol.handlers["bin-lookup"] = .init(data: Data(json.utf8), statusCode: statusCode)
    }

    /// Leaves "bin-lookup" unregistered so `MockURLProtocol` fails the request with
    /// `.notConnectedToInternet`, simulating a BIN-lookup network outage.
    static func removeBinLookup() {
        MockURLProtocol.handlers["bin-lookup"] = nil
    }

    static func setTokenizeSuccess(formToken: String = "tok_bug_demo", bin: String = "000000", lastFour: String = "0000") {
        let json = #"{"form_token":"\#(formToken)","card":{"bin":"\#(bin)","last_four_digits":"\#(lastFour)"}}"#
        MockURLProtocol.handlers["secure-fields"] = .init(data: Data(json.utf8), statusCode: 200)
    }

    /// The most recent tokenization request body, decoded as JSON, so a screen can display
    /// exactly what the SDK sent over the wire (e.g. `selected_network`, `birth_date`).
    static func lastTokenizePayloadJSON() -> [String: Any]? {
        guard let data = MockURLProtocol.capturedBodies["secure-fields"] else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func prettyPrintedLastTokenizePayload() -> String? {
        guard let data = MockURLProtocol.capturedBodies["secure-fields"],
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        return String(data: pretty, encoding: .utf8)
    }
}
#endif
