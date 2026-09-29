struct TokenizationPayload: Encodable {
    // Oney: when the CVV field is in birthdate mode its value is a "yyyy-MM-dd" date, not a
    // 3-4 digit PIN — the gateway's `cvv` field only accepts a PIN, and it accepts no birthdate
    // key at all (sending one is rejected with a 400). The date therefore never goes on the
    // wire — web and Android do the same — and the SDK reflects it back to the integrator
    // locally via `TokenizationResult.birthDate`. `cvv` is simply omitted in that mode.
    let cvv: String?
    // CVV-only: with no PAN field there is no card to describe, and the gateway wants the key
    // absent — not empty. A `card` carrying only `selected_network` is rejected for its missing
    // expiry (`INVALID_FORM`). So the body is literally `{"cvv": "…"}`, as on web and Android.
    let card: CardPayload?

    enum CodingKeys: String, CodingKey {
        case cvv
        case card
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(cvv, forKey: .cvv)
        try container.encodeIfPresent(card, forKey: .card)
    }

    struct CardPayload: Encodable {
        let pan: String
        // Optional so they can be omitted outright: a form configuring `pan` without `expDate`
        // sends a card block with no expiry and lets the gateway rule on it (INVALID_FORM), the
        // same shape and the same division of labour as Android's `buildRequestBody`.
        let expiryMonth: Int?
        let expiryYear: Int?
        let cardHolderName: String?
        let saveToken: Bool?
        let selectedNetwork: String

        enum CodingKeys: String, CodingKey {
            case pan
            case expiryMonth = "expiry_month"
            case expiryYear = "expiry_year"
            case cardHolderName = "card_holder_name"
            case saveToken = "save_token"
            case selectedNetwork = "selected_network"
        }
    }
}

struct TokenizationResponse: Decodable {
    let formToken: String
    /// Absent on a CVV-only tokenization: the gateway stored a cryptogram, not a card.
    let card: CardResponse?

    struct CardResponse: Decodable {
        let bin: String
        let lastFourDigits: String

        enum CodingKeys: String, CodingKey {
            case bin
            case lastFourDigits = "last_four_digits"
        }
    }

    enum CodingKeys: String, CodingKey {
        case formToken = "form_token"
        case card
    }
}

struct APIErrorResponse: Decodable {
    let error: String
}

struct BinLookupResult {
    struct BrandLengths {
        let panLengths: [Int]
        let cvvLengths: [Int]
    }

    let brands: [CardBrand]
    let panLengths: [Int]
    let cvvLengths: [Int]
    let perBrandLengths: [CardBrand: BrandLengths]

    var maxCvvLength: Int { cvvLengths.max() ?? 3 }
}

struct BinLookupResponse: Decodable {
    let brands: [BinBrand]?

    struct BinBrand: Decodable {
        let brand: String
        let isMain: Bool
        let panLengths: [Int]?
        let cvvLengths: [Int]?

        enum CodingKeys: String, CodingKey {
            case brand
            case isMain    = "is_main"
            case panLengths = "pan_lengths"
            case cvvLengths = "cvv_lengths"
        }
    }

    func toBinLookupResult() -> BinLookupResult {
        let parsed = brands ?? []
        let cardBrands = parsed.compactMap { CardBrand(apiValue: $0.brand) }
        let main = parsed.first { $0.isMain }

        var perBrand: [CardBrand: BinLookupResult.BrandLengths] = [:]
        for b in parsed {
            if let brand = CardBrand(apiValue: b.brand) {
                perBrand[brand] = BinLookupResult.BrandLengths(
                    panLengths: b.panLengths ?? [],
                    cvvLengths: b.cvvLengths ?? []
                )
            }
        }

        return BinLookupResult(
            brands: cardBrands,
            panLengths: main?.panLengths ?? [16],
            cvvLengths: main?.cvvLengths ?? [3],
            perBrandLengths: perBrand
        )
    }

}

struct BinLookupPayload: Encodable {
    let firstDigits: String

    enum CodingKeys: String, CodingKey {
        case firstDigits = "first_digits"
    }
}
