struct TokenizationPayload: Encodable {
    let cvv: String?
    let birthDate: String?
    let card: CardPayload

    enum CodingKeys: String, CodingKey {
        case cvv
        case birthDate = "birth_date"
        case card
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(cvv, forKey: .cvv)
        try container.encodeIfPresent(birthDate, forKey: .birthDate)
        try container.encode(card, forKey: .card)
    }

    struct CardPayload: Encodable {
        let pan: String
        let expiryMonth: Int
        let expiryYear: Int
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
    let card: CardResponse

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
    let brands: [CardBrand]
    let panLengths: [Int]
    let cvvLengths: [Int]

    var maxPanLength: Int { panLengths.max() ?? 16 }
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
        let cardBrands = parsed.compactMap { CardBrand(rawValue: Self.normaliseScheme($0.brand)) }
        let main = parsed.first { $0.isMain }
        return BinLookupResult(
            brands: cardBrands,
            panLengths: main?.panLengths ?? [16],
            cvvLengths: main?.cvvLengths ?? [3]
        )
    }

    // API returns "AMERICAN_EXPRESS" and "DINERS_CLUB"; map to our enum raw values
    private static func normaliseScheme(_ scheme: String) -> String {
        switch scheme {
        case "AMERICAN_EXPRESS": return "AMEX"
        case "DINERS_CLUB":      return "DINERS"
        case "CARTE_BANCAIRE":   return "CARTE_BANCAIRE" // already matches
        default:                 return scheme
        }
    }
}

struct BinLookupPayload: Encodable {
    let firstDigits: String

    enum CodingKeys: String, CodingKey {
        case firstDigits = "first_digits"
    }
}
