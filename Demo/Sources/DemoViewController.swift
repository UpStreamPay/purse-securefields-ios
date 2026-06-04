import UIKit
import PurseSecureFields

final class DemoViewController: UIViewController {

    // MARK: - SecureFields

    let manager = SecureFieldsManager(config: SecureFieldsConfig(
        tenantId: "61ff8a6a-edd5-4f40-aa32-8410a73e79ac",
        baseURL: "https://api.vault.purse-test.com",
        placeholders: SecureFieldsPlaceholders(
            pan: "1234 5678 9012 3456",
            cvv: "123",
            expDate: "MM/YY",
            holderName: "Name Surname"
        )
    ))

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

    var cvvContainerView: UIView!
    var expiryContainerView: UIView!
    var holderContainerView: UIView!

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
        title = "SecureFields Demo"
        view.backgroundColor = .systemBackground
        manager.delegate = self
        setupLayout()
        payButton.addTarget(self, action: #selector(payTapped), for: .touchUpInside)
        clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
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
        debugLabel.text = """
        PAN     length=\(panLength)  valid=\(panValid ? "✓" : "✗")
        CVV     valid=\(cvvValid ? "✓" : "✗")
        Expiry  valid=\(expiryValid ? "✓" : "✗")
        Brands  \(brands)
        Form    \(formValid ? "✓ ready" : "✗ incomplete")
        """
    }

    // MARK: - Actions

    @objc private func payTapped() {
        resultLabel.textColor = .secondaryLabel
        resultLabel.text = "Submitting…"
        payButton.isEnabled = false
        manager.submit()
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
        cvvSectionLabel.text = "CVV"
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
