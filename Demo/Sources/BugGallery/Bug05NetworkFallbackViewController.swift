#if DEBUG
import UIKit
import PurseSecureFields

/// Bug #5 — Two defaults compound into a silent lie: when the BIN lookup fails entirely (or
/// returns brands outside the configured `brands` list), `scheduleBinLookup`'s completion handler
/// bails out on `guard case .success = result else { return }` — `detectedBrands` stays empty and
/// `panField.validLengths` stays at its default `[16]` (SecureFieldsManager.swift ~line 275). A
/// real 16-digit Mastercard number still passes length+Luhn and the form still becomes "valid".
/// Then in `submit()`, `let selectedBrand = brandSelectorView.selectedBrand ?? detectedBrands.first ?? .visa`
/// falls all the way through to the hardcoded `.visa` default, so `selected_network` is sent as
/// `"VISA"` for a card that was never even identified, let alone Visa.
final class Bug05NetworkFallbackViewController: BugBaseViewController {

    private let mastercardPAN = "5555555555554444" // real Mastercard test PAN, Luhn-valid, 16 digits

    private let manager = BugSecureFieldsFactory.make() // all brands allowed — irrelevant here, BIN never resolves
    private var payloadLabel: UILabel!
    private var debugLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Bug #5"
        MockScenarios.reset()
        MockScenarios.removeBinLookup() // BIN lookup will fail with .notConnectedToInternet
        MockScenarios.setTokenizeSuccess()
        manager.delegate = self

        addHeader(
            number: 5,
            title: "selected_network arbitraire quand le BIN lookup échoue",
            steps: [
                "Le BIN lookup est volontairement non mocké ici : chaque appel échoue en réseau (comme une vraie panne serveur).",
                "Tapez « Remplir une Mastercard valide » — un vrai numéro de test Mastercard, Luhn-correct, 16 chiffres.",
                "Constatez dans le panneau Debug que le formulaire devient quand même valide (aucune marque n'a pourtant été identifiée).",
                "Tapez « Envoyer (submit) » puis regardez le payload intercepté : selected_network.",
            ],
            expected: "Soit le submit refuse d'envoyer une carte dont la marque n'a pas pu être vérifiée, soit selected_network reflète honnêtement l'absence de marque détectée (ou la détection locale par IIN) — jamais une marque choisie au hasard.",
            observed: "detectedBrands reste vide (le bloc `guard case .success = result else { return }` abandonne silencieusement en cas d'échec réseau) donc validLengths reste au défaut [16], qui matche une Mastercard réelle : le formulaire est jugé valide. Puis submit() calcule `selectedBrand = brandSelectorView.selectedBrand ?? detectedBrands.first ?? .visa` — les deux premiers termes sont nil, donc selected_network est envoyé en dur comme \"VISA\", peu importe la carte réellement saisie."
        )

        stackView.addArrangedSubview(sectionLabel("Numéro de carte"))
        stackView.addArrangedSubview(manager.panContainer)

        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 12
        row.distribution = .fillEqually
        let cvvStack = UIStackView()
        cvvStack.axis = .vertical
        cvvStack.spacing = 6
        cvvStack.addArrangedSubview(sectionLabel("CVV"))
        cvvStack.addArrangedSubview(fieldContainer(manager.cvvView))
        let expStack = UIStackView()
        expStack.axis = .vertical
        expStack.spacing = 6
        expStack.addArrangedSubview(sectionLabel("Expiration"))
        expStack.addArrangedSubview(fieldContainer(manager.expDateView))
        row.addArrangedSubview(cvvStack)
        row.addArrangedSubview(expStack)
        stackView.addArrangedSubview(row)

        stackView.addArrangedSubview(makeButton("Remplir une Mastercard valide (\(mastercardPAN))", action: #selector(fillCard)))
        stackView.addArrangedSubview(makeButton("Envoyer (submit)", action: #selector(submitAndCapture)))

        debugLabel = addDebugPanel(title: "Debug — brands détectées / validité")
        payloadLabel = UILabel()
        payloadLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        payloadLabel.numberOfLines = 0
        payloadLabel.text = "(pas encore de submit)"
        stackView.addArrangedSubview(sectionLabel("Payload de tokenisation intercepté"))
        stackView.addArrangedSubview(panel(payloadLabel))

        refreshDebugPanel()
    }

    @objc private func fillCard() {
        guard let panField = manager.panContainer.firstTextField(),
              let cvvField = manager.cvvView.firstTextField(),
              let expField = manager.expDateView.firstTextField() else { return }
        panField.simulateTyping(mastercardPAN)
        cvvField.simulateTyping("123")
        expField.simulateTyping("1230")
    }

    @objc private func submitAndCapture() {
        payloadLabel.text = "Envoi en cours…"
        manager.submit()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refreshPayloadLabel() }
    }

    private func refreshPayloadLabel() {
        guard let pretty = MockScenarios.prettyPrintedLastTokenizePayload() else {
            payloadLabel.text = "(aucun payload capturé — le formulaire était-il valide ?)"
            return
        }
        let network = MockScenarios.lastTokenizePayloadJSON()
            .flatMap { $0["card"] as? [String: Any] }
            .flatMap { $0["selected_network"] as? String } ?? "?"
        payloadLabel.text = "selected_network envoyé = \"\(network)\"  (carte réellement saisie : Mastercard)\n\n\(pretty)"
    }

    private func refreshDebugPanel() {
        debugLabel.text = """
        detectedBrands (via délégué) = aucune (le lookup BIN échoue toujours)
        manager.isFieldValid(.pan)   = \(manager.isFieldValid(.pan) ? "✓ (BUG : valide sans marque identifiée)" : "✗")
        manager.isFieldValid(.cvv)   = \(manager.isFieldValid(.cvv) ? "✓" : "✗")
        """
    }
}

extension Bug05NetworkFallbackViewController: SecureFieldsDelegate {
    func secureFieldsContentChanged() { refreshDebugPanel() }
    func secureFieldsFormValidityChanged(_ isValid: Bool) { refreshDebugPanel() }
    func secureFieldsDidTokenize(_ result: TokenizationResult) { refreshPayloadLabel() }
    func secureFieldsDidFail(_ error: SecureFieldsError) {
        payloadLabel.text = "Échec du submit — le formulaire est-il complet ?"
    }
}
#endif
