#if DEBUG
import UIKit
import PurseSecureFields

/// Bug #6 — `SecurePANField.textDidChange()` (Views/SecurePANField.swift:32-39) unconditionally
/// runs `selectedTextRange = textRange(from: end, to: end)` after every edit, forcing the caret
/// to the very end of the field regardless of where the cardholder was actually editing. Trying
/// to fix a typo in the middle of a card number is impossible: any edit teleports the cursor to
/// the end.
final class Bug06CursorJumpViewController: BugBaseViewController {

    private let pan16 = "4111111111111111"

    private let manager = BugSecureFieldsFactory.make()
    private var debugLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Bug #6"
        MockScenarios.reset()
        manager.delegate = self

        addHeader(
            number: 6,
            title: "Le curseur du PAN est toujours renvoyé en fin de champ",
            steps: [
                "Manuellement : tapez dans le champ « Numéro de carte », saisissez 16 chiffres.",
                "Placez le curseur (tap ou glissé) juste après le 5ᵉ chiffre.",
                "Effacez un chiffre (⌫) puis retapez un chiffre au même endroit.",
                "Constatez que le chiffre s'insère à la FIN du champ, pas à l'endroit où vous avez tapé.",
                "Ou utilisez le bouton « Reproduire automatiquement » ci-dessous pour un scénario scripté et déterministe (même bug, sans dépendre de la précision du tap).",
            ],
            expected: "Après avoir positionné le curseur au milieu du numéro puis tapé/effacé un chiffre, le curseur doit rester juste après le chiffre modifié, pas sauter en fin de champ.",
            observed: "textDidChange() réassigne toujours selectedTextRange = (end, end) après reformatage, quelle que soit la position d'édition précédente. Toute correction au milieu du PAN est impossible au clavier : chaque frappe repousse le curseur à la fin."
        )

        stackView.addArrangedSubview(sectionLabel("Numéro de carte"))
        stackView.addArrangedSubview(manager.panContainer)

        stackView.addArrangedSubview(makeButton("Reproduire automatiquement", action: #selector(runAutomatedRepro)))

        debugLabel = addDebugPanel(title: "Debug — position du curseur")
        debugLabel.text = "(appuyez sur « Reproduire automatiquement »)"
    }

    @objc private func runAutomatedRepro() {
        guard let panField = manager.panContainer.firstTextField() else { return }
        panField.becomeFirstResponder()
        panField.simulateTyping(pan16)

        // Move the caret to just after the 5th digit — CardFormatter renders "4111 1111 1111 1111",
        // so UTF-16 offset 6 lands right after the 5th digit (4 digits + 1 space + 1 digit).
        let targetOffset = 6
        panField.moveCaret(toOffset: targetOffset)
        let beforeOffset = panField.caretOffsetFromStart ?? -1

        // A real keystroke at the caret position — `insertText` is the same UIKeyInput entry
        // point UIKit calls when the on-screen keyboard is tapped, so this is not a shortcut
        // around the bug, it's the same code path a human tester would exercise.
        panField.insertText("9")

        let afterOffset = panField.caretOffsetFromStart ?? -1
        let totalLength = panField.offset(from: panField.beginningOfDocument, to: panField.endOfDocument)

        debugLabel.text = """
        Curseur positionné manuellement après le 5ᵉ chiffre : offset = \(beforeOffset)
        Curseur après une frappe supplémentaire (insertText) : offset = \(afterOffset)
        Longueur totale du champ formaté                     : offset = \(totalLength)

        \(afterOffset == totalLength ? "❌ BUG confirmé : le curseur a été renvoyé en fin de champ au lieu de rester proche de la position éditée." : "✅ le curseur est resté proche de la position éditée.")
        """
    }
}

extension Bug06CursorJumpViewController: SecureFieldsDelegate {}
#endif
