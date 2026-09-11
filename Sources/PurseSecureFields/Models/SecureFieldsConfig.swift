import UIKit

public struct SecureFieldsStyle {
    /// Appearance overrides for one field state. Every property is optional: `nil` inherits the
    /// base style, so a theme only states what actually changes in that state.
    public struct StateStyle {
        public let textColor: UIColor?
        public let backgroundColor: UIColor?
        public let borderColor: UIColor?
        public let borderWidth: CGFloat?

        public init(
            textColor: UIColor? = nil,
            backgroundColor: UIColor? = nil,
            borderColor: UIColor? = nil,
            borderWidth: CGFloat? = nil
        ) {
            self.textColor = textColor
            self.backgroundColor = backgroundColor
            self.borderColor = borderColor
            self.borderWidth = borderWidth
        }
    }

    public let font: UIFont
    public let textColor: UIColor
    public let placeholderColor: UIColor
    public let tintColor: UIColor
    public let keyboardAppearance: UIKeyboardAppearance

    public let backgroundColor: UIColor?
    public let borderColor: UIColor?
    public let borderWidth: CGFloat
    public let cornerRadius: CGFloat

    /// State-dependent overrides, resolved in this order for a field: `focus` while it is the
    /// first responder, then `valid` or `invalid` once it has content, and `empty` while it has
    /// none. The first match wins; anything a state leaves `nil` falls back to the base style.
    /// Mirrors the `focus` / `valid` / `invalid` / `empty` pseudo-classes of `VaultStyles` on
    /// Android and of the web SDK's CSS.
    public let focus: StateStyle?
    public let valid: StateStyle?
    public let invalid: StateStyle?
    public let empty: StateStyle?

    public static let `default` = SecureFieldsStyle()

    public init(
        font: UIFont = .systemFont(ofSize: 16),
        textColor: UIColor = .label,
        placeholderColor: UIColor = .placeholderText,
        tintColor: UIColor = .systemBlue,
        keyboardAppearance: UIKeyboardAppearance = .default,
        backgroundColor: UIColor? = nil,
        borderColor: UIColor? = nil,
        borderWidth: CGFloat = 0,
        cornerRadius: CGFloat = 0,
        focus: StateStyle? = nil,
        valid: StateStyle? = nil,
        invalid: StateStyle? = nil,
        empty: StateStyle? = nil
    ) {
        self.font = font
        self.textColor = textColor
        self.placeholderColor = placeholderColor
        self.tintColor = tintColor
        self.keyboardAppearance = keyboardAppearance
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.cornerRadius = cornerRadius
        self.focus = focus
        self.valid = valid
        self.invalid = invalid
        self.empty = empty
    }

    /// The overrides that apply to a field in the given state, or nil when none is configured.
    func stateStyle(isFocused: Bool, isValid: Bool, hasContent: Bool) -> StateStyle? {
        if isFocused, let focus { return focus }
        if hasContent { return isValid ? valid : invalid }
        return empty
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

/// Per-field options. Every property is optional: a `nil` placeholder falls back to the legacy
/// `SecureFieldsPlaceholders` entry for that field, so the two configuration styles compose.
public struct SecureFieldConfig {
    /// Placeholder shown while the field is empty. Overrides `SecureFieldsPlaceholders` when set.
    public let placeholder: String?
    /// VoiceOver label for the field (`UIView.accessibilityLabel`). The field's *value* stays
    /// hidden from the accessibility API regardless — only the label is exposed.
    public let accessibilityLabel: String?

    public init(placeholder: String? = nil, accessibilityLabel: String? = nil) {
        self.placeholder = placeholder
        self.accessibilityLabel = accessibilityLabel
    }
}

/// Which fields the form renders, and how. Presence decides rendering: a field left `nil` is
/// not part of the form — it is hidden, excluded from `secureFieldsFormValidityChanged`, from
/// the `submit()` completeness check, and from the tokenization request. `cvv` is the only
/// mandatory field, so a configuration holding just `cvv` is the **CVV-only** form used to
/// renew the cryptogram of a card already on file. Mirrors `SecureFieldsFieldsConfig` on Android
/// and the `fields` object of the web SDK.
///
/// A configured `pan` requires a configured `expDate`: the gateway rejects a card without an
/// expiry and `submit()` has no expiry override to supply one.
public struct SecureFieldsFieldsConfig {
    public let pan: SecureFieldConfig?
    public let expDate: SecureFieldConfig?
    public let holderName: SecureFieldConfig?
    public let cvv: SecureFieldConfig

    /// All four fields, with no per-field overrides — the pre-`fields` behaviour.
    public static let all = SecureFieldsFieldsConfig(pan: .init(), expDate: .init(), holderName: .init(), cvv: .init())

    /// The CVV field alone.
    public static let cvvOnly = SecureFieldsFieldsConfig(cvv: .init())

    public init(
        pan: SecureFieldConfig? = nil,
        expDate: SecureFieldConfig? = nil,
        holderName: SecureFieldConfig? = nil,
        cvv: SecureFieldConfig = .init()
    ) {
        precondition(pan == nil || expDate != nil,
                     "SecureFields: a configured `pan` field requires a configured `expDate` field")
        self.pan = pan
        self.expDate = expDate
        self.holderName = holderName
        self.cvv = cvv
    }

    /// The fields present in this configuration. Always contains `.cvv`.
    public var configuredFields: Set<SecureField> {
        var set: Set<SecureField> = [.cvv]
        if pan != nil { set.insert(.pan) }
        if expDate != nil { set.insert(.expDate) }
        if holderName != nil { set.insert(.holderName) }
        return set
    }

    /// True when no PAN field is configured — the form then tokenizes the CVV on its own.
    public var isCVVOnly: Bool { pan == nil }

    func config(for field: SecureField) -> SecureFieldConfig? {
        switch field {
        case .pan:        return pan
        case .expDate:    return expDate
        case .holderName: return holderName
        case .cvv:        return cvv
        }
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

    /// Which fields the form renders. Defaults to all four. See `SecureFieldsFieldsConfig` —
    /// a configuration holding only `cvv` is the CVV-only form.
    public let fields: SecureFieldsFieldsConfig

    /// When true, the cardholder name counts toward `secureFieldsFormValidityChanged` and the
    /// `submit()` completeness check. Defaults to false: the field is optional at tokenization,
    /// and a host that never mounts `holderNameView` must not end up with a form that can never
    /// become valid. Has no effect when `fields` leaves `holderName` out.
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
        fields: SecureFieldsFieldsConfig = .all,
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
        self.fields = fields
        self.requiresHolderName = requiresHolderName
        self.pinnedPublicKeyHashes = pinnedPublicKeyHashes
        self.apiKey = apiKey
        self.monitoringEnabled = monitoringEnabled
    }
}
