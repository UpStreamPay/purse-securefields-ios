import Foundation
import Testing
@testable import PurseSecureFields

/// Pins the tokenization wire contract: the birthdate must never reach the
/// gateway — under any key. Web and Android send nothing for it (the SDK reflects the date back
/// to the integrator locally), and the gateway rejects a request carrying it with a 400 — the
/// exact failure that made every Oney submission fail on iOS.
struct TokenizationPayloadTests {

    private func encodeToJSON(_ payload: TokenizationPayload) throws -> [String: Any] {
        let data = try JSONEncoder().encode(payload)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func makeCard() -> TokenizationPayload.CardPayload {
        .init(
            pan: "5032026098999722327",
            expiryMonth: 12,
            expiryYear: 2030,
            cardHolderName: "Jane Doe",
            saveToken: false,
            selectedNetwork: "ONEY"
        )
    }

    @Test func oneyPayloadCarriesNeitherCvvNorBirthdate() throws {
        let payload = TokenizationPayload(cvv: nil, card: makeCard())

        let json = try encodeToJSON(payload)

        #expect(json["cvv"] == nil)
        #expect(json["birth_date"] == nil)
        #expect(json["card"] != nil)
    }

    @Test func regularPayloadCarriesCvvOnly() throws {
        let payload = TokenizationPayload(cvv: "123", card: makeCard())

        let json = try encodeToJSON(payload)

        #expect(json["cvv"] as? String == "123")
        #expect(json["birth_date"] == nil)
    }

    /// CVV-only: the body must be `{"cvv": "…"}` and nothing else. The gateway wants
    /// `card` absent — a `card` holding only `selected_network` is rejected for its missing expiry.
    @Test func cvvOnlyPayloadCarriesOnlyTheCvv() throws {
        let payload = TokenizationPayload(cvv: "1234", card: nil)

        let json = try encodeToJSON(payload)

        #expect(json["cvv"] as? String == "1234")
        #expect(json["card"] == nil, "a CVV-only request must not carry a `card` key, not even an empty one")
        #expect(json.count == 1)
    }

    @Test func cardPayloadUsesSnakeCaseKeys() throws {
        let payload = TokenizationPayload(cvv: "123", card: makeCard())

        let json = try encodeToJSON(payload)
        let card = try #require(json["card"] as? [String: Any])

        #expect(card["pan"] as? String == "5032026098999722327")
        #expect(card["expiry_month"] as? Int == 12)
        #expect(card["expiry_year"] as? Int == 2030)
        #expect(card["card_holder_name"] as? String == "Jane Doe")
        #expect(card["save_token"] as? Bool == false)
        #expect(card["selected_network"] as? String == "ONEY")
    }
}
