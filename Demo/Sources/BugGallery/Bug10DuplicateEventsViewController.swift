#if DEBUG
import UIKit
import PurseSecureFields

/// Bug #10 — AGENTS.md documents the contract explicitly: "secureFieldsFormValidityChanged(_:) —
/// fires only when overall form validity flips." `SecureFieldsManager.notifyFormValidity()`
/// (SecureFieldsManager.swift ~line 307-310) does not honour that: it recomputes
/// `panField.isValid && cvvField.isValid && expDateField.isValid` and calls
/// `delegate?.secureFieldsFormValidityChanged(valid)` unconditionally, with no memoized
/// "did this actually change" check (unlike `SecureBaseField.setValidity`, which *does* guard on
/// `newValid != isValid`). Every completed BIN lookup calls `notifyFormValidity()` regardless of
/// whether the combined result changed, so typing a PAN slowly enough for the debounced BIN
/// lookup to fire more than once produces several identical `secureFieldsFormValidityChanged(false)`
/// events in a row.
final class Bug10DuplicateEventsViewController: BugBaseViewController {

    private let pan16 = "9000000000000001" // Luhn-valid 16-digit test PAN, distinct fictitious BIN

    private let manager = BugSecureFieldsFactory.make()
    private let eventLog = EventLogView()
    private let counter = RepeatCounter()
    private var debugLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Bug #10"
        MockScenarios.reset()
        MockScenarios.setBinLookup([MockBinBrand(.visa, isMain: true, panLengths: [16])])
        manager.delegate = self

        addHeader(
            number: 10,
            title: "secureFieldsFormValidityChanged émis en boucle avec la même valeur",
            steps: [
                "Tapez « Simuler la saisie (avec pauses) » : le PAN est tapé chiffre par chiffre avec ~400 ms entre chaque, pour laisser le debounce de 300 ms du lookup BIN se déclencher plusieurs fois (à 6, 7 puis 8 chiffres).",
                "Regardez le journal ci-dessous : plusieurs secureFieldsFormValidityChanged(false) consécutifs, alors que la validité globale du formulaire ne change jamais entre ces émissions.",
                "Le compteur « répétitions consécutives » ci-dessous en fait la synthèse.",
            ],
            expected: "Conformément à AGENTS.md (« fires only when overall form validity flips »), secureFieldsFormValidityChanged ne doit être émis qu'au moment où la validité globale bascule réellement (par exemple false → true).",
            observed: "notifyFormValidity() envoie systématiquement la valeur recalculée au délégué, sans comparer à la dernière valeur émise. Chaque lookup BIN abouti (un par préfixe distinct de 6, 7 puis 8 chiffres) redéclenche un envoi, même si le résultat (false) est identique à chaque fois."
        )

        stackView.addArrangedSubview(sectionLabel("Numéro de carte"))
        stackView.addArrangedSubview(manager.panContainer)

        stackView.addArrangedSubview(makeButton("Simuler la saisie (avec pauses)", action: #selector(runTimedTyping)))
        stackView.addArrangedSubview(makeTintedButton("Réinitialiser", action: #selector(resetDemo)))

        debugLabel = addDebugPanel(title: "Compteur d'émissions")
        stackView.addArrangedSubview(sectionLabel("Journal des événements secureFieldsFormValidityChanged"))
        stackView.addArrangedSubview(eventLog)

        refreshDebugPanel()
    }

    @objc private func runTimedTyping() {
        guard let panField = manager.panContainer.firstTextField() else { return }
        eventLog.log("(script) début de la saisie chiffre par chiffre, pause 400 ms")
        panField.simulateTypingWithDelay(pan16, delay: 0.4, onEachCharacter: { [weak self] current in
            self?.eventLog.log("(script) frappe → \(current.count) chiffre(s)")
        }, completion: { [weak self] in
            self?.eventLog.log("(script) saisie terminée")
        })
    }

    @objc private func resetDemo() {
        counter.reset()
        eventLog.clear()
        manager.clearFields()
        refreshDebugPanel()
    }

    private func refreshDebugPanel() {
        debugLabel.text = """
        Émissions totales               = \(counter.totalEmissions)
        Émissions redondantes (bug)     = \(counter.redundantEmissions)
        Série actuelle de valeurs identiques = \(counter.streak)
        Dernière valeur émise            = \(counter.lastValue.map { $0 ? "true" : "false" } ?? "—")

        \(counter.streak > 1 ? "❌ BUG confirmé : \(counter.streak) émissions consécutives avec la même valeur." : "Tapez « Simuler la saisie » pour déclencher le bug.")
        """
    }
}

extension Bug10DuplicateEventsViewController: SecureFieldsDelegate {
    func secureFieldsFormValidityChanged(_ isValid: Bool) {
        let (isRepeat, streak) = counter.record(isValid)
        let marker = isRepeat ? "  ← répétition #\(streak) de la même valeur (violation du contrat)" : ""
        eventLog.log("secureFieldsFormValidityChanged(\(isValid))\(marker)")
        refreshDebugPanel()
    }
}
#endif
