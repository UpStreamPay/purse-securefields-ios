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

    /// SHA-256 hashes (Base64-encoded) of the vault server's SubjectPublicKeyInfo (SPKI).
    ///
    /// When non-empty, every request to `baseURL` is rejected unless the server presents a
    /// certificate whose public key matches at least one hash — preventing MITM attacks even
    /// when a rogue root CA is installed on the device (MDM/BYOD profiles, malware).
    ///
    /// Supported key types: RSA-2048, RSA-4096, EC-256 (P-256), EC-384 (P-384).
    ///
    /// Best practice: provide at least **two** hashes (primary + one rotation backup) so a
    /// certificate renewal does not break existing app versions in the field.
    ///
    /// To extract a hash from a live server:
    /// ```
    /// openssl s_client -connect <host>:443 2>/dev/null </dev/null \
    ///   | openssl x509 -pubkey -noout \
    ///   | openssl pkey -pubin -outform DER \
    ///   | openssl dgst -sha256 -binary \
    ///   | base64
    /// ```
    public let pinnedPublicKeyHashes: [String]

    #if DEBUG
    public var testURLSession: URLSession? = nil
    #endif

    public init(
        tenantId: String,
        baseURL: String,
        brands: [CardBrand] = CardBrand.allCases,
        style: SecureFieldsStyle = .default,
        placeholders: SecureFieldsPlaceholders = .init(),
        pinnedPublicKeyHashes: [String] = []
    ) {
        precondition(baseURL.hasPrefix("https://"), "SecureFields: baseURL must use HTTPS")
        precondition(!tenantId.trimmingCharacters(in: .whitespaces).isEmpty, "SecureFields: tenantId must not be empty")
        self.tenantId = tenantId
        self.baseURL = baseURL
        self.brands = brands
        self.style = style
        self.placeholders = placeholders
        self.pinnedPublicKeyHashes = pinnedPublicKeyHashes
    }
}
