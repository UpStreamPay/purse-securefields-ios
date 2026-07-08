#if DEBUG
import UIKit
import PurseSecureFields

/// Bug #7 — `SecureBaseField.clearSensitiveData()` sets `text = ""; isValid = false` directly,
/// bypassing `setValidity()` (Views/SecureBaseField.swift:71-74) — so `onValidityChanged` never
/// fires from that path. When the cardholder switches the selected brand on a co-badged card,
/// `SecureFieldsManager.setupBrandSelector()`'s `onBrandSelected` closure (SecureFieldsManager.swift
/// ~line 156-192) calls `applySelectedBrand(brand)`, which calls `cvvField.setInputMode(.cvv)` —
/// that wipes the auto-valid Oney birthdate via `clearSensitiveData()`, but the closure never
/// calls `notifyFormValidity()` afterwards. The form silently becomes invalid (CVV is now empty)
/// while the host app's last known state still says "valid".
final class Bug07MissingInvalidationViewController: BugBaseViewController {

    // 19-digit, Luhn-valid PAN whose mocked BIN response lists Oney first (auto-selected) and
    // Carte Bancaire second (co-badged card).
    private let coBadgedPAN = "5000000000000000005"

    private let manager = BugSecureFieldsFactory.make(brands: [.oney, .carteBancaire])
    private let eventLog = EventLogView()
    private var debugLabel: UILabel!
    private var lastReportedFormValid: Bool?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Bug #7"
        MockScenarios.reset()
        MockScenarios.setBinLookup([
            MockBinBrand(.oney, isMain: true, panLengths: [19]),
            MockBinBrand(.carteBancaire, isMain: false, panLengths: [19]),
        ])
        manager.delegate = self

        addHeader(
            number: 7,
            title: "Changement de marque : le CVV est vidé sans notifier l'invalidation",
            steps: [
                "Tapez « 1. Remplir carte co-badgée » : PAN Oney/CB + expiration. Oney est auto-sélectionné, la date de naissance devient automatiquement valide (bug #4) → le formulaire complet devient valide (voir le journal : formValidityChanged(true)).",
                "Tapez « 2. Basculer sur Carte Bancaire » (équivalent à taper le chip CB).",
                "Regardez le journal des événements : aucun nouvel événement formValidityChanged n'apparaît, alors que le CVV vient d'être vidé.",
            ],
            expected: "Changer de marque vide le CVV (Oney → CB change le mode de saisie) ; le formulaire devient réellement invalide, donc secureFieldsFormValidityChanged(false) doit être émis immédiatement.",
            observed: "cvvField.setInputMode(.cvv) appelle clearSensitiveData(), qui met isValid=false directement sans passer par setValidity() — onValidityChanged ne se déclenche donc jamais. Le closure onBrandSelected de setupBrandSelector() n'appelle pas non plus notifyFormValidity(). Résultat : le dernier événement connu du host dit encore \"valide\", alors que manager.isFieldValid(.cvv) est déjà retombé à faux."
        )

        stackView.addArrangedSubview(sectionLabel("Numéro de carte (co-badgée Oney / CB)"))
        stackView.addArrangedSubview(manager.panContainer)

        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 12
        row.distribution = .fillEqually
        let cvvStack = UIStackView()
        cvvStack.axis = .vertical
        cvvStack.spacing = 6
        cvvStack.addArrangedSubview(sectionLabel("CVV / Date de naissance"))
        cvvStack.addArrangedSubview(fieldContainer(manager.cvvView))
        let expStack = UIStackView()
        expStack.axis = .vertical
        expStack.spacing = 6
        expStack.addArrangedSubview(sectionLabel("Expiration"))
        expStack.addArrangedSubview(fieldContainer(manager.expDateView))
        row.addArrangedSubview(cvvStack)
        row.addArrangedSubview(expStack)
        stackView.addArrangedSubview(row)

        stackView.addArrangedSubview(makeButton("1. Remplir carte co-badgée (PAN + expiration)", action: #selector(fillCard)))
        stackView.addArrangedSubview(makeButton("2. Basculer sur Carte Bancaire (= taper le chip CB)", action: #selector(switchToCB)))

        debugLabel = addDebugPanel(title: "Debug — dernier état connu vs état réel")
        stackView.addArrangedSubview(sectionLabel("Journal des callbacks du délégué"))
        stackView.addArrangedSubview(eventLog)

        refreshDebugPanel()
    }

    @objc private func fillCard() {
        guard let panField = manager.panContainer.firstTextField() else { return }
        panField.simulateTyping(coBadgedPAN)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, let expField = self.manager.expDateView.firstTextField() else { return }
            expField.simulateTyping("1230")
            self.refreshDebugPanel()
        }
    }

    @objc private func switchToCB() {
        // Equivalent to the cardholder tapping the "CB" brand chip inside panContainer's
        // SecureBrandSelectorView. The chip control itself is private, but it's a real UIControl
        // in the view hierarchy, so we can find it the same way a UI test would locate a button.
        guard let chip = findBrandChip(brand: .carteBancaire) else {
            eventLog.log("⚠️ Chip Carte Bancaire introuvable — avez-vous rempli le PAN d'abord ?")
            return
        }
        chip.sendActions(for: .touchUpInside)
        refreshDebugPanel()
    }

    private func findBrandChip(brand: CardBrand) -> UIControl? {
        // BrandChip is a private UIControl subclass; we can't name its type from here, but we can
        // find a plausible candidate by walking the selector view's control subviews and matching
        // by relative order (Oney is index 0 = main, CB is index 1, per our mocked BIN order).
        func controls(in view: UIView) -> [UIControl] {
            var result: [UIControl] = []
            for sub in view.subviews {
                if let control = sub as? UIControl, !(control is UITextField) { result.append(control) }
                result.append(contentsOf: controls(in: sub))
            }
            return result
        }
        let chips = controls(in: manager.panContainer)
        let index = brand == .oney ? 0 : 1
        guard index < chips.count else { return nil }
        return chips[index]
    }

    private func refreshDebugPanel() {
        debugLabel.text = """
        Dernier formValidityChanged reçu = \(lastReportedFormValid.map { $0 ? "true" : "false" } ?? "aucun")
        manager.isFieldValid(.cvv) (réel) = \(manager.isFieldValid(.cvv) ? "✓" : "✗")
        manager.isFieldValid(.pan) (réel) = \(manager.isFieldValid(.pan) ? "✓" : "✗")

        \(lastReportedFormValid == true && !manager.isFieldValid(.cvv) ? "❌ BUG confirmé : le host croit encore le formulaire valide, mais le CVV réel est invalide." : "")
        """
    }
}

extension Bug07MissingInvalidationViewController: SecureFieldsDelegate {
    func secureFieldsFormValidityChanged(_ isValid: Bool) {
        lastReportedFormValid = isValid
        eventLog.log("secureFieldsFormValidityChanged(\(isValid))")
        refreshDebugPanel()
    }

    func secureFieldsBrandSelected(_ brand: CardBrand) {
        eventLog.log("secureFieldsBrandSelected(\(brand.rawValue))")
        refreshDebugPanel()
    }

    func secureFieldsBrandsDetected(_ brands: [CardBrand]) {
        eventLog.log("secureFieldsBrandsDetected(\(brands.map(\.rawValue)))")
    }
}
#endif
