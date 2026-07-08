#if DEBUG
import UIKit
import PurseSecureFields

/// Bug #9 — `submit()` (SecureFieldsManager.swift ~line 340-346) only calls `clearSensitiveData()`
/// on the four fields before the network call — it never resets `detectedBrands`,
/// `panField.validLengths`, `cvvField.validLengths`, the brand selector chips, or
/// `cvvField`'s input mode back to `.cvv`. This is actually documented as intentional in
/// AGENTS.md ("BIN/brand state reset is still host-triggered" — the host must call
/// `clearFields()` itself). The bug this screen demonstrates is how easy it is to miss that: a
/// host app that naively reacts to `secureFieldsDidTokenize` without also calling
/// `manager.clearFields()` leaves the CVV field permanently stuck in birthdate mode for the next
/// card the cardholder tries to enter — a genuine, confusing UX regression that the SDK does
/// nothing to prevent or warn about.
final class Bug09StaleStateViewController: BugBaseViewController {

    private let oneyPAN = "8000000000000000002"

    private let manager = BugSecureFieldsFactory.make(brands: [.oney])
    private var debugLabel: UILabel!
    private var statusLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Bug #9"
        MockScenarios.reset()
        MockScenarios.setBinLookup([MockBinBrand(.oney, isMain: true, panLengths: [19])])
        MockScenarios.setTokenizeSuccess()
        manager.delegate = self

        addHeader(
            number: 9,
            title: "État résiduel (marques, longueurs, mode CVV) après une tokenisation réussie",
            steps: [
                "Tapez « 1. Remplir + envoyer une carte Oney » : PAN + expiration Oney, puis submit() automatique.",
                "Une fois le succès affiché, les 4 champs sont vidés — mais tapez maintenant sur le champ CVV/date ci-dessus.",
                "Constatez qu'il ouvre une roue de sélection de date (mode Oney), et non le clavier numérique attendu pour une prochaine carte « normale ».",
            ],
            expected: "Après une tokenisation réussie affichée au host via secureFieldsDidTokenize, si l'app ne fait rien de plus, le formulaire vide devrait au moins présenter un clavier neutre — pas rester verrouillé sur les marques/longueurs/mode de saisie de la carte précédente.",
            observed: "submit() n'appelle que clearSensitiveData() (texte + validité) sur chaque champ, jamais clearFields() (qui, lui, réinitialiserait aussi validLengths, les chips de marque et cvvField.setInputMode(.cvv)). Le champ CVV reste donc en mode birthdate : hasFieldContent(.cvv) répond même « vrai » juste après le submit, alors que le champ est visuellement vide, car ce getter renvoie vrai dès que inputMode == .birthdate.",
            limitation: "C'est un comportement documenté dans AGENTS.md comme volontaire (« BIN/brand state reset is still host-triggered », le host doit rappeler manager.clearFields() lui-même) — mais rien dans l'API ne le signale au moment du succès, et c'est exactement le genre d'appel qu'une intégration réelle oublie facilement. Cet écran le montre tel quel, sans appeler clearFields() après le succès, pour illustrer le piège."
        )

        stackView.addArrangedSubview(sectionLabel("Numéro de carte (Oney)"))
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

        stackView.addArrangedSubview(makeButton("1. Remplir + envoyer une carte Oney", action: #selector(fillAndSubmit)))

        statusLabel = UILabel()
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.numberOfLines = 0
        statusLabel.textColor = .secondaryLabel
        statusLabel.text = "(pas encore envoyé)"
        stackView.addArrangedSubview(statusLabel)

        debugLabel = addDebugPanel(title: "Debug — état résiduel après le submit")
        refreshDebugPanel()
    }

    @objc private func fillAndSubmit() {
        guard let panField = manager.panContainer.firstTextField() else { return }
        panField.simulateTyping(oneyPAN)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, let expField = self.manager.expDateView.firstTextField() else { return }
            expField.simulateTyping("1230")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.statusLabel.text = "Envoi en cours…"
                self?.manager.submit()
            }
        }
    }

    private func refreshDebugPanel() {
        debugLabel.text = """
        manager.hasFieldContent(.cvv) = \(manager.hasFieldContent(.cvv) ? "✓ (vrai même si le champ est vide, car inputMode == .birthdate)" : "✗")
        manager.isFieldValid(.pan)    = \(manager.isFieldValid(.pan) ? "✓" : "✗")

        Après le succès : tapez le champ CVV/date ci-dessus. Roue de date = bug confirmé.
        """
    }
}

extension Bug09StaleStateViewController: SecureFieldsDelegate {
    func secureFieldsDidTokenize(_ result: TokenizationResult) {
        statusLabel.text = "✅ Tokenisé : \(result.vaultFormToken) — les champs sont vides mais PAS remis à zéro (pas de clearFields())."
        refreshDebugPanel()
    }

    func secureFieldsDidFail(_ error: SecureFieldsError) {
        statusLabel.text = "Échec du submit."
    }

    func secureFieldsContentChanged() { refreshDebugPanel() }
}
#endif
