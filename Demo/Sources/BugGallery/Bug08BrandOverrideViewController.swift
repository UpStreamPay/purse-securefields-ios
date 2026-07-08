#if DEBUG
import UIKit
import PurseSecureFields

/// Bug #8 — `SecureBrandSelectorView.update(brands:)` (Views/SecureBrandSelectorView.swift:40-44)
/// always resets `selectedBrand = brands.first` inside `rebuildChips`. Every time a *new* BIN
/// lookup completes — including one triggered by editing the PAN after the cardholder already
/// tapped a brand chip manually — `SecureFieldsManager` calls `brandSelectorView.update(brands:)`
/// again (SecureFieldsManager.swift ~line 231), silently discarding the manual selection and
/// reverting to the first/default brand. No `secureFieldsBrandSelected` delegate event fires for
/// this reversal, because that callback only fires from the chip's own tap handler.
final class Bug08BrandOverrideViewController: BugBaseViewController {

    // 8-digit co-badged prefix (Oney first / main, Carte Bancaire second).
    private let coBadgedPrefix = "50000000"

    private let manager = BugSecureFieldsFactory.make(brands: [.oney, .carteBancaire])
    private let eventLog = EventLogView()
    private var debugLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Bug #8"
        MockScenarios.reset()
        MockScenarios.setBinLookup([
            MockBinBrand(.oney, isMain: true, panLengths: [19]),
            MockBinBrand(.carteBancaire, isMain: false, panLengths: [19]),
        ])
        manager.delegate = self

        addHeader(
            number: 8,
            title: "La sélection manuelle de marque est écrasée par un nouveau lookup BIN",
            steps: [
                "Tapez « 1. Taper 8 chiffres (co-badgé) » — Oney est auto-sélectionné (1ʳᵉ marque de la réponse BIN).",
                "Tapez le chip « Carte Bancaire » pour la sélectionner manuellement.",
                "Tapez « 2. Effacer 1 chiffre puis le retaper (avec pause) » : ce bouton attend ~1s après avoir effacé le dernier chiffre (le temps que le debounce de 300ms relance un lookup BIN sur le nouveau préfixe à 7 chiffres), puis retape le chiffre.",
                "Regardez le journal : la sélection revient à Oney (1ʳᵉ marque) sans qu'aucun secureFieldsBrandSelected n'ait été journalisé.",
            ],
            expected: "Une fois que le porteur a choisi manuellement une marque parmi les marques co-badgées, ce choix doit être conservé tant que les marques disponibles ne changent pas réellement (même prefix, mêmes marques).",
            observed: "brandSelectorView.update(brands:) réinitialise toujours selectedBrand = brands.first dans rebuildChips(), y compris quand le nouveau lookup renvoie exactement les mêmes marques dans le même ordre. La sélection manuelle de l'utilisateur est perdue silencieusement, sans événement secureFieldsBrandSelected pour prévenir le host."
        )

        stackView.addArrangedSubview(sectionLabel("Numéro de carte (co-badgée Oney / CB)"))
        stackView.addArrangedSubview(manager.panContainer)

        stackView.addArrangedSubview(makeButton("1. Taper 8 chiffres (co-badgé)", action: #selector(fillPrefix)))
        stackView.addArrangedSubview(makeButton("2. Effacer 1 chiffre puis le retaper (avec pause)", action: #selector(deleteAndRetype)))

        debugLabel = addDebugPanel(title: "Debug")
        stackView.addArrangedSubview(sectionLabel("Journal des callbacks du délégué"))
        stackView.addArrangedSubview(eventLog)

        refreshDebugPanel()
    }

    @objc private func fillPrefix() {
        guard let panField = manager.panContainer.firstTextField() else { return }
        panField.simulateTyping(coBadgedPrefix)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.refreshDebugPanel() }
    }

    @objc private func deleteAndRetype() {
        guard let panField = manager.panContainer.firstTextField() else { return }
        let sevenDigits = String(coBadgedPrefix.dropLast())
        eventLog.log("(script) suppression du dernier chiffre → \(sevenDigits)")
        panField.simulateTyping(sevenDigits)
        // Wait past the 300ms debounce so the 7-digit BIN lookup actually resolves and resets
        // the brand selector before we retype the digit.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            self.eventLog.log("(script) re-saisie du chiffre → \(self.coBadgedPrefix)")
            panField.simulateTyping(self.coBadgedPrefix)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.refreshDebugPanel() }
        }
    }

    private func refreshDebugPanel() {
        debugLabel.text = """
        Astuce : tapez le chip « Carte Bancaire » ci-dessus après l'étape 1, puis lancez l'étape 2.
        Regardez ensuite quelle marque est surlignée dans le sélecteur — si elle est revenue à
        Oney sans que le journal ci-dessous n'affiche de secureFieldsBrandSelected(CARTE_BANCAIRE)
        après votre tap manuel, le bug est confirmé.
        """
    }
}

extension Bug08BrandOverrideViewController: SecureFieldsDelegate {
    func secureFieldsBrandSelected(_ brand: CardBrand) {
        eventLog.log("secureFieldsBrandSelected(\(brand.rawValue))  ← déclenché seulement par un tap utilisateur sur un chip")
    }

    func secureFieldsBrandsDetected(_ brands: [CardBrand]) {
        eventLog.log("secureFieldsBrandsDetected(\(brands.map(\.rawValue)))  ← un nouveau lookup vient de (re)passer, la sélection a pu être réinitialisée sans notification")
    }
}
#endif
