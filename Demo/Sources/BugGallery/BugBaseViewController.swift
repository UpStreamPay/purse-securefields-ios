#if DEBUG
import UIKit

/// Shared scaffolding for every "Bug #N" reproduction screen: a scrollable stack view with a
/// yellow "steps to reproduce" card at the top, plus small helpers that mirror the visual style
/// already used by `DemoViewController+Layout` (secondarySystemBackground rounded containers,
/// monospaced debug labels) so the gallery feels consistent with the rest of the demo app.
class BugBaseViewController: UIViewController {

    let scrollView = UIScrollView()
    let stackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = 16
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupScaffold()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Scaffold

    private func setupScaffold() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    @objc private func keyboardWillChange(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let inset = max(0, view.bounds.maxY - frame.minY)
        scrollView.contentInset.bottom = inset
        scrollView.verticalScrollIndicatorInsets.bottom = inset
    }

    // MARK: - Steps header

    /// Adds the "how to reproduce this bug" card. Always shown at the very top of the screen,
    /// in French, per the reproduction-gallery brief.
    func addHeader(number: Int, title: String, steps: [String], expected: String, observed: String, limitation: String? = nil) {
        let card = UIView()
        card.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.12)
        card.layer.cornerRadius = 12
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor.systemYellow.withAlphaComponent(0.45).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        let inner = UIStackView()
        inner.axis = .vertical
        inner.spacing = 8
        inner.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.font = .boldSystemFont(ofSize: 17)
        titleLabel.numberOfLines = 0
        titleLabel.text = "Bug #\(number) — \(title)"

        let stepsLabel = UILabel()
        stepsLabel.font = .systemFont(ofSize: 14)
        stepsLabel.numberOfLines = 0
        let numbered = steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        stepsLabel.text = "Étapes de reproduction :\n\(numbered)"

        let expectedLabel = UILabel()
        expectedLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        expectedLabel.numberOfLines = 0
        expectedLabel.textColor = .systemGreen
        expectedLabel.text = "✅ Attendu : \(expected)"

        let observedLabel = UILabel()
        observedLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        observedLabel.numberOfLines = 0
        observedLabel.textColor = .systemRed
        observedLabel.text = "❌ Observé (bug) : \(observed)"

        inner.addArrangedSubview(titleLabel)
        inner.addArrangedSubview(stepsLabel)
        inner.addArrangedSubview(expectedLabel)
        inner.addArrangedSubview(observedLabel)

        if let limitation {
            let limitLabel = UILabel()
            limitLabel.font = .italicSystemFont(ofSize: 12)
            limitLabel.numberOfLines = 0
            limitLabel.textColor = .secondaryLabel
            limitLabel.text = "⚠️ Limite de cette démo : \(limitation)"
            inner.addArrangedSubview(limitLabel)
        }

        card.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
        ])
        stackView.addArrangedSubview(card)
    }

    // MARK: - Shared visual helpers (mirrors DemoViewController+Layout styling)

    func sectionLabel(_ text: String) -> UILabel {
        let lbl = UILabel()
        lbl.text = text
        lbl.font = .systemFont(ofSize: 13, weight: .semibold)
        lbl.textColor = .secondaryLabel
        return lbl
    }

    func divider() -> UIView {
        let v = UIView()
        v.backgroundColor = .separator
        v.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return v
    }

    /// Wraps a secure field view (e.g. `manager.cvvView`) in the same rounded container used by
    /// the main demo screen.
    func fieldContainer(_ view: UIView) -> UIView {
        view.translatesAutoresizingMaskIntoConstraints = false
        let container = UIView()
        container.backgroundColor = .secondarySystemBackground
        container.layer.cornerRadius = 10
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            container.heightAnchor.constraint(equalToConstant: 48),
        ])
        return container
    }

    /// Puts an arbitrary view (e.g. a UILabel) inside a rounded "panel" background, matching the
    /// existing demo's debug panel look.
    func panel(_ inner: UIView, padding: CGFloat = 12) -> UIView {
        let container = UIView()
        container.backgroundColor = .secondarySystemBackground
        container.layer.cornerRadius = 8
        inner.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: container.topAnchor, constant: padding),
            inner.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            inner.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            inner.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -padding),
        ])
        return container
    }

    /// Adds a titled monospaced debug label (for showing live SDK state) and returns it so the
    /// caller can keep updating `.text`.
    @discardableResult
    func addDebugPanel(title: String = "Debug") -> UILabel {
        stackView.addArrangedSubview(divider())
        stackView.addArrangedSubview(sectionLabel(title))
        let label = UILabel()
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.numberOfLines = 0
        label.textColor = .label
        label.text = "—"
        stackView.addArrangedSubview(panel(label))
        return label
    }

    func makeButton(_ title: String, action: Selector) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.baseBackgroundColor = .systemBlue
        let btn = UIButton(configuration: config)
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }

    func makeTintedButton(_ title: String, action: Selector) -> UIButton {
        var config = UIButton.Configuration.tinted()
        config.title = title
        let btn = UIButton(configuration: config)
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }
}
#endif
