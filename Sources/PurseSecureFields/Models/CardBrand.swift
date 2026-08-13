public enum CardBrand: String, CaseIterable, Equatable {
    case visa = "VISA"
    case mastercard = "MASTERCARD"
    case amex = "AMEX"
    case maestro = "MAESTRO"
    case carteBancaire = "CARTE_BANCAIRE"
    case oney = "ONEY"

    /// Accepts the enum raw values and the vault API's scheme vocabulary — the API says
    /// "AMERICAN_EXPRESS" where the enum raw value is "AMEX". Any configuration that crosses a
    /// JSON boundary (React Native / Flutter bridge, server-pushed config, test harness) can use
    /// either spelling instead of silently dropping the brand.
    public init?(apiValue: String) {
        switch apiValue {
        case "AMERICAN_EXPRESS": self = .amex
        default: self.init(rawValue: apiValue)
        }
    }
}
