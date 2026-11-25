import UIKit
import PurseSecureFields

final class DemoViewController: UIViewController {

    // MARK: - SecureFields

    lazy var manager: SecureFieldsManager = makeManager()

    /// Whether this screen runs the CVV-only form: the cryptogram-renewal flow for a card already
    /// on file. Only the CVV view is mounted and `submit()` sends `{"cvv": "…"}` alone.
    ///
    /// Switch modes with the "Full form / CVV only" control in the navigation bar — the config is
    /// immutable after init, so the screen is rebuilt in the chosen mode. `--cvv-only` on the
    /// launch arguments starts the demo directly in CVV-only mode (used by the UI tests).
    let isCVVOnly: Bool

    init(isCVVOnly: Bool = ProcessInfo.processInfo.arguments.contains("--cvv-only")) {
        self.isCVVOnly = isCVVOnly
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var fields: SecureFieldsFieldsConfig {
        isCVVOnly
            ? SecureFieldsFieldsConfig(cvv: .init(placeholder: "123 or 1234", accessibilityLabel: "Security code"))
            : .all
    }

    /// "Full form / CVV only" — rebuilds the screen in the chosen mode. Mounted as the first row
    /// of the form (see `setupLayout`), not in the navigation bar: the XCUITests tap the bar to
    /// dismiss the keyboard, and a title-view control would swallow that tap and switch modes.
    lazy var modeControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["Full form", "CVV only"])
        control.selectedSegmentIndex = isCVVOnly ? 1 : 0
        control.accessibilityIdentifier = "mode_control"
        control.addTarget(self, action: #selector(modeChanged(_:)), for: .valueChanged)
        return control
    }()

    @objc private func modeChanged(_ sender: UISegmentedControl) {
        let next = DemoViewController(isCVVOnly: sender.selectedSegmentIndex == 1)
        navigationController?.setViewControllers([next], animated: false)
    }

    /// CVV-only: the saved card's brand, as the merchant would know it. `Any` leaves the SDK on the
    /// union of the configured brands (3 or 4 digits); a brand calls `selectBrand(_:)` and narrows
    /// the field to that brand's length — watch the CVV label and the debug panel.
    static let demoBrands: [(title: String, brand: CardBrand?)] = [
        ("Any", nil), ("Visa", .visa), ("MC", .mastercard), ("Amex", .amex), ("CB", .carteBancaire),
    ]

    /// Asks `submit()` for the Purse 3DS chain, then — with a merchant backend — plays the
    /// advanced-flow payment and challenge (`DemoBackend`). Off by default, so the plain
    /// tokenization stays one tap away.
    lazy var threeDSSwitch: UISwitch = {
        let control = UISwitch()
        control.isOn = false
        control.accessibilityIdentifier = "three_ds_switch"
        return control
    }()

    /// The eligible `creditcard` PSPs, as the merchant backend listed them at launch.
    lazy var pspControl: UISegmentedControl = {
        let control = UISegmentedControl(items: DemoBackend.cardSolutions.map(\.partner))
        control.selectedSegmentIndex = DemoBackend.selectedSolution
        control.accessibilityIdentifier = "psp_control"
        control.addTarget(self, action: #selector(pspChanged(_:)), for: .valueChanged)
        return control
    }()

    @objc private func pspChanged(_ sender: UISegmentedControl) {
        DemoBackend.selectedSolution = sender.selectedSegmentIndex
        updateDebugPanel()
    }

    lazy var brandControl: UISegmentedControl = {
        let control = UISegmentedControl(items: Self.demoBrands.map(\.title))
        control.selectedSegmentIndex = 0
        control.accessibilityIdentifier = "brand_control"
        control.addTarget(self, action: #selector(brandChanged(_:)), for: .valueChanged)
        return control
    }()

    @objc private func brandChanged(_ sender: UISegmentedControl) {
        guard let brand = Self.demoBrands[sender.selectedSegmentIndex].brand else {
            // Back to "Any": the SDK has no un-select, so rebuild the CVV-only screen.
            navigationController?.setViewControllers([DemoViewController(isCVVOnly: true)], animated: false)
            return
        }
        manager.selectBrand(brand)
        updateCVVLabel()
        updateDebugPanel()
        updateFieldBorders()
    }

    /// "CVV (3 or 4 digits)" etc. — reflects `expectedLengths(for: .cvv)`, or the Oney date mode.
    func updateCVVLabel(isOney: Bool = false) {
        if isOney {
            cvvSectionLabel.text = "Date of Birth"
            return
        }
        let lengths = manager.expectedLengths(for: .cvv).map(String.init).joined(separator: " or ")
        cvvSectionLabel.text = "CVV (\(lengths) digits)"
    }

    private func makeManager() -> SecureFieldsManager {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            // The URL itself is irrelevant here — MockURLProtocol intercepts by path suffix,
            // not host, so requests never actually leave the device regardless of environment.
            var config = SecureFieldsConfig(
                tenantId: "test",
                environment: .test,
                // Opt in: the selector is hidden by default, and the demo exists to show it.
                brandSelector: true,
                placeholders: SecureFieldsPlaceholders(
                    pan: "1234 5678 9012 3456",
                    cvv: "123",
                    expDate: "MM/YY",
                    holderName: "Name Surname"
                ),
                fields: fields
            )
            config.urlSessionOverride = MockURLProtocol.makeSession()
            return SecureFieldsManager(config: config)
        }
        #endif
        return SecureFieldsManager(config: SecureFieldsConfig(
            tenantId: Self.tenantId,
            environment: .test,
            brandSelector: true,
            placeholders: SecureFieldsPlaceholders(
                pan: "1234 5678 9012 3456",
                cvv: "123",
                expDate: "MM/YY",
                holderName: "Name Surname"
            ),
            fields: fields,
            // The key also goes on the 3DS calls as `X-Api-Key`: the gateway wants one on
            // challenge-result. Monitoring stays off unless `.env` names a key of its own.
            apiKey: Self.monitoringApiKey ?? Self.gatewayAPIKey,
            monitoringEnabled: Self.monitoringApiKey != nil,
            appSDKConfiguration: Self.appSDKConfiguration
        ))
    }

    /// The `data` of `GET /v2/entities/{entityId}/app-sdk-configuration`, loaded once at launch
    /// by `SceneDelegate` — a static because the mode switch rebuilds this controller.
    static var appSDKConfiguration: String?

    /// The merchant's public API key, from the same backend. See `DemoBackend.gatewayAPIKey()`.
    static var gatewayAPIKey: String?

    // Set via env vars when launching Xcode/xcodebuild, or a gitignored .env file loaded with
    // `source scripts/load-env.sh` (see Demo/Resources/Info.plist) — never commit real values
    // here. Falls back to a shared sandbox tenant when unset, so the demo still runs out of
    // the box.
    private static var tenantId: String {
        // The Purse Vault tenant of the 3DS demo entity — `DemoBackend.entityId`'s default.
        DemoBackend.setting("TENANT_ID") ?? "61ff8a6a-edd5-4f40-aa32-8410a73e79ac"
    }

    // Blank when unset, which leaves remote log monitoring disabled.
    private static var monitoringApiKey: String? { DemoBackend.setting("MONITORING_API_KEY") }

    // MARK: - UI

    let scrollView = UIScrollView()
    let stackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = 12
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    let payButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Pay"
        config.baseBackgroundColor = .systemBlue
        let btn = UIButton(configuration: config)
        btn.isEnabled = false
        return btn
    }()

    /// `authentication.challenge_data`. Filled in by the advanced flow when the issuer asks for a
    /// challenge; paste one by hand to replay a challenge from a payment made elsewhere.
    /// Base64url, unpadded, exactly as the API returned it.
    lazy var challengeField: UITextField = {
        let field = UITextField()
        field.placeholder = "paste authentication.challenge_data"
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.clearButtonMode = .whileEditing
        field.accessibilityIdentifier = "challenge_field"
        return field
    }()

    lazy var challengeButton: UIButton = {
        var config = UIButton.Configuration.tinted()
        config.title = "Run 3DS challenge"
        config.baseBackgroundColor = .systemIndigo
        let btn = UIButton(configuration: config)
        btn.accessibilityIdentifier = "challenge_button"
        return btn
    }()

    let clearButton: UIButton = {
        var config = UIButton.Configuration.tinted()
        config.title = "Clear"
        config.baseBackgroundColor = .systemGray
        config.baseForegroundColor = .secondaryLabel
        return UIButton(configuration: config)
    }()


    let debugLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        lbl.numberOfLines = 0
        lbl.textColor = .secondaryLabel
        lbl.text = "—"
        return lbl
    }()

    let resultLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        lbl.numberOfLines = 0
        lbl.textColor = .label
        return lbl
    }()

    // MARK: - Field containers (for border feedback)

    // Only the containers of configured fields exist — see `manager.configuredFields`.
    var cvvContainerView: UIView!
    var expiryContainerView: UIView?
    var holderContainerView: UIView?

    // MARK: - State

    var panLength = 0
    var panValid = false
    var cvvValid = false
    var expiryValid = false
    var detectedBrands: [CardBrand] = []
    var formValid = false
    var cvvSectionLabel: UILabel!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = manager.isCVVOnly ? "SecureFields Demo — CVV only" : "SecureFields Demo"
        view.backgroundColor = .systemBackground
        manager.delegate = self
        setupLayout()
        updateFieldBorders()
        updateDebugPanel()
        payButton.addTarget(self, action: #selector(payTapped), for: .touchUpInside)
        clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
        challengeButton.addTarget(self, action: #selector(challengeTapped), for: .touchUpInside)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    // MARK: - Debug

    func updateDebugPanel() {
        let brands = detectedBrands.isEmpty ? "none" : detectedBrands.map(\.rawValue).joined(separator: ", ")
        let fields = manager.configuredFields.map { String(describing: $0) }.sorted().joined(separator: ", ")
        let cvvLengths = manager.expectedLengths(for: .cvv)
        let selected = manager.selectedBrand?.rawValue ?? "none"
        let threeDS = manager.isThreeDSAvailable
            ? "✓ provider linked" + (manager.threeDSWarnings.isEmpty
                ? ""
                : " · \(manager.threeDSWarnings.count) warning(s)")
            : (PurseThreeDS.provider == nil ? "✗ no provider" : "✗ no app SDK configuration")
        let psp = DemoBackend.cardSolution.map { "\($0.partner) · \($0.method)" }
            ?? (DemoBackend.baseURL == nil ? "— no merchant backend" : "— no creditcard solution / backend unreachable")
        debugLabel.text = """
        Fields  \(fields)
        PAN     length=\(panLength)  valid=\(panValid ? "✓" : "✗")
        CVV     valid=\(cvvValid ? "✓" : "✗")  expects=\(cvvLengths)  brand=\(selected)
        Expiry  valid=\(expiryValid ? "✓" : "✗")
        Brands  \(brands)
        Form    \(formValid ? "✓ ready" : "✗ incomplete")
        3DS     \(threeDS)
        PSP     \(psp)
        Entity  \(DemoBackend.baseURL == nil ? "—" : DemoBackend.entityId)
        """
    }

    // MARK: - Actions

    @objc private func payTapped() {
        resultLabel.textColor = .secondaryLabel
        resultLabel.text = "Submitting…"
        payButton.isEnabled = false
        manager.submit(threeDSEnabled: threeDSSwitch.isOn)
    }

    @objc private func challengeTapped() {
        let blob = (challengeField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !blob.isEmpty else {
            resultLabel.textColor = .systemRed
            resultLabel.text = "Paste challenge_data from the payment response first."
            return
        }
        view.endEditing(true)
        resultLabel.textColor = .secondaryLabel
        resultLabel.text = "Running challenge…"
        runChallenge(blob, paymentID: nil)
    }

    @objc private func clearTapped() {
        manager.clearFields()
        resultLabel.text = nil
        panLength = 0
        panValid = false
        cvvValid = false
        expiryValid = false
        detectedBrands = []
        formValid = false
        updateCVVLabel()
        updateDebugPanel()
        updateFieldBorders()
    }

    @objc private func keyboardWillChange(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let inset = max(0, view.bounds.maxY - frame.minY)
        scrollView.contentInset.bottom = inset
        scrollView.verticalScrollIndicatorInsets.bottom = inset
    }
}
