#if DEBUG
import UIKit
import PurseSecureFields

/// Bug #2 — `SecureFieldsManager.scheduleBinLookup` (SecureFieldsManager.swift, around line 196-230)
/// sets `panField.validLengths = binResult.panLengths`, where `binResult.panLengths` comes from
/// `BinLookupResponse.toBinLookupResult()`'s `main?.panLengths` — i.e. the length of whichever
/// brand the API marked `is_main`, *not* the brand that ends up auto-selected in the UI. When the
/// config only allows Oney but the BIN response's `is_main` brand is VISA (16 digits) while ONEY
/// needs 19, the field is stuck expecting 16 digits even though the only usable brand is Oney.
final class Bug02OneyLengthViewController: BugBaseViewController {

    // 19-digit, Luhn-valid PAN used only to demonstrate the bug (fictitious BIN).
    private let oneyPAN = "4000000000000000006"

    private let manager = BugSecureFieldsFactory.make(brands: [.oney])
    private var debugLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Bug #2"
        MockScenarios.reset()
        MockScenarios.setBinLookup([
            MockBinBrand(.visa, isMain: true, panLengths: [16]),
            MockBinBrand(.oney, isMain: false, panLengths: [19]),
        ])
        manager.delegate = self

        addHeader(
            number: 2,
            title: "validLengths reste [16] alors qu'Oney (19 chiffres) est la seule marque affichée",
            steps: [
                "Le SDK est configuré avec brands: [.oney] et un BIN mocké qui renvoie VISA (is_main, pan_lengths [16]) + ONEY (pan_lengths [19]).",
                "Tapez le bouton « Remplir un PAN Oney 19 chiffres » ci-dessous (ou saisissez vous-même les 19 chiffres affichés).",
                "Observez le panneau Debug : Oney est la seule marque proposée, mais validLengths reste [16].",
            ],
            expected: "Puisque la config restreint les marques à Oney, validLengths doit suivre la longueur d'Oney (19) : un PAN de 19 chiffres valides (Luhn) doit rendre le champ PAN valide.",
            observed: "panField.validLengths est fixé à binResult.panLengths, qui vient de la marque marquée is_main dans la réponse BIN (ici VISA, 16), et pas de la marque réellement sélectionnée/autorisée (Oney, 19). Un PAN Oney de 19 chiffres ne valide donc jamais, même Luhn-correct."
        )

        stackView.addArrangedSubview(sectionLabel("Numéro de carte"))
        stackView.addArrangedSubview(manager.panContainer)

        let fillButton = makeButton("Remplir un PAN Oney 19 chiffres (\(oneyPAN))", action: #selector(fillPAN))
        stackView.addArrangedSubview(fillButton)

        debugLabel = addDebugPanel()
        refreshDebugPanel()
    }

    @objc private func fillPAN() {
        guard let panField = manager.panContainer.firstTextField() else { return }
        panField.simulateTyping(oneyPAN)
    }

    private func refreshDebugPanel() {
        debugLabel.text = """
        PAN saisi (chiffres)          = \(manager.panDigitCount)
        manager.isFieldValid(.pan)    = \(manager.isFieldValid(.pan) ? "✓" : "✗")

        Attendu  : validLengths = [19] (Oney est la seule marque autorisée par la config)
        Observé  : validLengths = [16] (repris de la marque "is_main" du BIN, ici VISA)
        """
    }
}

extension Bug02OneyLengthViewController: SecureFieldsDelegate {
    func secureFieldsContentChanged() { refreshDebugPanel() }
    func secureFieldsFormValidityChanged(_ isValid: Bool) { refreshDebugPanel() }
    func secureFieldsBrandsDetected(_ brands: [CardBrand]) { refreshDebugPanel() }
}
#endif
