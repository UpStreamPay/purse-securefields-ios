import UIKit

public struct SecureFieldsStyle {
    public let font: UIFont
    public let textColor: UIColor
    public let placeholderColor: UIColor
    public let tintColor: UIColor
    public let keyboardAppearance: UIKeyboardAppearance

    public static let `default` = SecureFieldsStyle()

    public init(
        font: UIFont = .systemFont(ofSize: 16),
        textColor: UIColor = .label,
        placeholderColor: UIColor = .placeholderText,
        tintColor: UIColor = .systemBlue,
        keyboardAppearance: UIKeyboardAppearance = .default
    ) {
        self.font = font
        self.textColor = textColor
        self.placeholderColor = placeholderColor
        self.tintColor = tintColor
        self.keyboardAppearance = keyboardAppearance
    }
}

public struct SecureFieldsPlaceholders {
    public let pan: String
    public let cvv: String
    public let expDate: String
    public let holderName: String

    public init(
        pan: String = "1234 5678 9012 3456",
        cvv: String = "123",
        expDate: String = "MM/YY",
        holderName: String = "Cardholder Name"
    ) {
        self.pan = pan
        self.cvv = cvv
        self.expDate = expDate
        self.holderName = holderName
    }
}

public struct SecureFieldsConfig {
    public let tenantId: String
    public let baseURL: String
    public let brands: [CardBrand]
    public let style: SecureFieldsStyle
    public let placeholders: SecureFieldsPlaceholders

    #if DEBUG
    public var testURLSession: URLSession? = nil
    #endif

    public init(
        tenantId: String,
        baseURL: String,
        brands: [CardBrand] = CardBrand.allCases,
        style: SecureFieldsStyle = .default,
        placeholders: SecureFieldsPlaceholders = .init()
    ) {
        precondition(baseURL.hasPrefix("https://"), "SecureFields: baseURL must use HTTPS")
        precondition(!tenantId.trimmingCharacters(in: .whitespaces).isEmpty, "SecureFields: tenantId must not be empty")
        self.tenantId = tenantId
        self.baseURL = baseURL
        self.brands = brands
        self.style = style
        self.placeholders = placeholders
    }
}
