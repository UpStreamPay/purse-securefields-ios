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

    /// `SANDBOX`/`PRODUCTION` (or the internal-only `TEST` in Debug builds). The SDK resolves
    /// both the tokenization gateway and the remote monitoring endpoint internally — no raw URL
    /// configuration is required in the host app. See `VaultEnvironment`.
    public let environment: VaultEnvironment

    public let brands: [CardBrand]

    /// Whether the cardholder may arbitrate the network of a co-badged card through the built-in
    /// brand selector. Defaults to `false`, matching the web and Android SDKs: the selector stays
    /// hidden and the SDK submits the brand its own resolution picked (the merchant's
    /// `brands` order expresses that preference). Set it to `true` to show the chips.
    ///
    /// When enabled, the cardholder's pick wins over any `selectedNetwork` passed to `submit`.
    public let brandSelector: Bool

    public let style: SecureFieldsStyle
    public let placeholders: SecureFieldsPlaceholders

    /// When true, the cardholder name counts toward `secureFieldsFormValidityChanged` and the
    /// `submit()` completeness check. Defaults to false: the field is optional at tokenization,
    /// and a host that never mounts `holderNameView` must not end up with a form that can never
    /// become valid. Mirrors the Android rule "a configured field counts".
    public let requiresHolderName: Bool

    /// SHA-256 hashes (Base64-encoded) of the vault server's SubjectPublicKeyInfo (SPKI).
    ///
    /// When non-empty, every request to the tokenization gateway is rejected unless the server
    /// presents a certificate whose public key matches at least one hash — preventing MITM
    /// attacks even when a rogue root CA is installed on the device (MDM/BYOD profiles, malware).
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

    /// Api key used to authenticate remote log monitoring (Datadog, via the widget log worker).
    /// Monitoring silently disables itself when omitted.
    public let apiKey: String?

    /// Opt-out for remote log monitoring. Defaults to enabled. Events are sent as they happen —
    /// safety comes from every payload being structural metadata only, never card data — see
    /// `RemoteLogger`.
    public let monitoringEnabled: Bool

    /// Substitutes the `URLSession` used for BIN lookup and tokenization.
    ///
    /// **Tests only.** A session set here bypasses certificate pinning entirely, so it must never
    /// be set in a shipping app. It exists outside `#if DEBUG` because the distributed
    /// XCFramework is built in Release: gated, no consumer of the binary — including our own E2E
    /// suite — could stub the gateway at all.
    ///
    /// Remote log monitoring builds its own session and is not affected; disable it with
    /// `monitoringEnabled: false` when running against a stub.
    public var urlSessionOverride: URLSession? = nil

    public init(
        tenantId: String,
        environment: VaultEnvironment = .sandbox,
        brands: [CardBrand] = CardBrand.allCases,
        brandSelector: Bool = false,
        style: SecureFieldsStyle = .default,
        placeholders: SecureFieldsPlaceholders = .init(),
        requiresHolderName: Bool = false,
        pinnedPublicKeyHashes: [String] = [],
        apiKey: String? = nil,
        monitoringEnabled: Bool = true
    ) {
        precondition(!tenantId.trimmingCharacters(in: .whitespaces).isEmpty, "SecureFields: tenantId must not be empty")
        self.tenantId = tenantId
        self.environment = environment
        self.brands = brands
        self.brandSelector = brandSelector
        self.style = style
        self.placeholders = placeholders
        self.requiresHolderName = requiresHolderName
        self.pinnedPublicKeyHashes = pinnedPublicKeyHashes
        self.apiKey = apiKey
        self.monitoringEnabled = monitoringEnabled
    }
}
