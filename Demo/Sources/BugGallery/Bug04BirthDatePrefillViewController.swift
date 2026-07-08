#if DEBUG
import UIKit
import PurseSecureFields

/// Bug #4 — `SecureCVVField.configureForMode()` (Views/SecureCVVField.swift:43-56), when switching
/// to `.birthdate` mode, immediately calls `applyBirthdate(from: picker)` using the
/// `UIDatePicker`'s default date (today, since nothing was set yet) and calls `setValidity(true)`
/// — before the cardholder has touched the picker at all. The moment a BIN lookup resolves to
/// Oney, the "date of birth" field silently becomes valid with today's date as the value.
final class Bug04BirthDatePrefillViewController: BugBaseViewController {

    private let oneyPrefix = "70000000" // 8 digits is enough to trigger + lock in the BIN lookup

    private let manager = BugSecureFieldsFactory.make(brands: [.oney])
    private var debugLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Bug #4"
        MockScenarios.reset()
        MockScenarios.setBinLookup([MockBinBrand(.oney, isMain: true, panLengths: [19])])
        manager.delegate = self

        addHeader(
            number: 4,
            title: "Champ « date de naissance » valide sans aucune saisie",
            steps: [
                "Tapez « Taper 8 chiffres d'un BIN Oney » ci-dessous — NE touchez PAS au champ CVV/date, ne cliquez sur aucun picker.",
                "Attendez ~1 seconde (le temps du lookup BIN + son debounce de 300 ms).",
                "Observez le panneau Debug ci-dessous, et le champ « Date de naissance » lui-même : il affiche déjà la date du jour.",
            ],
            expected: "Le champ date de naissance doit rester vide et invalide tant que le porteur n'a pas choisi explicitement sa date de naissance dans le picker.",
            observed: "Dès que le brand détecté est Oney, configureForMode() appelle applyBirthdate(from: picker) avec la date par défaut du UIDatePicker (aujourd'hui) et marque le champ valide (setValidity(true)) — sans aucune interaction de l'utilisateur. hasFieldContent(.cvv) et isFieldValid(.cvv) passent à vrai instantanément."
        )

        stackView.addArrangedSubview(sectionLabel("Numéro de carte"))
        stackView.addArrangedSubview(manager.panContainer)

        stackView.addArrangedSubview(sectionLabel("Date de naissance (ne pas toucher)"))
        stackView.addArrangedSubview(fieldContainer(manager.cvvView))

        stackView.addArrangedSubview(makeButton("Taper 8 chiffres d'un BIN Oney (\(oneyPrefix))", action: #selector(fillBin)))

        debugLabel = addDebugPanel()
        refreshDebugPanel()
    }

    @objc private func fillBin() {
        guard let panField = manager.panContainer.firstTextField() else { return }
        panField.simulateTyping(oneyPrefix)
        // Poll for ~1.5s so the debug panel updates the instant the BIN lookup resolves, without
        // requiring the user to touch anything else.
        for delay in stride(from: 0.1, through: 1.5, by: 0.1) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.refreshDebugPanel() }
        }
    }

    private func refreshDebugPanel() {
        debugLabel.text = """
        manager.isFieldValid(.cvv)    = \(manager.isFieldValid(.cvv) ? "✓ (BUG : valide sans saisie)" : "✗")
        manager.hasFieldContent(.cvv) = \(manager.hasFieldContent(.cvv) ? "✓" : "✗")

        Regardez aussi le champ ci-dessus : il doit déjà afficher la date du jour au format aaaa-MM-jj.
        """
    }
}

extension Bug04BirthDatePrefillViewController: SecureFieldsDelegate {
    func secureFieldsContentChanged() { refreshDebugPanel() }
    func secureFieldsFormValidityChanged(_ isValid: Bool) { refreshDebugPanel() }
    func secureFieldsBrandsDetected(_ brands: [CardBrand]) { refreshDebugPanel() }
}
#endif
