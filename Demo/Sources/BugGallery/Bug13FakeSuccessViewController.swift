#if DEBUG
import UIKit
import PurseSecureFields

/// Bug #13 — `VaultAPIClient.binLookup` (VaultAPIClient.swift ~line 89-90): when the BIN lookup
/// response body can't be decoded as `BinLookupResponse` (malformed/unexpected JSON), the code
/// does NOT report a decoding failure — it fabricates a fake successful `BinLookupResult` with
/// `brands: []`, `panLengths: [16]`, `cvvLengths: [3]`, and calls `completion(.success(...))`
/// anyway:
/// ```
/// let result = (try? JSONDecoder().decode(BinLookupResponse.self, from: data))?.toBinLookupResult()
///     ?? BinLookupResult(brands: [], panLengths: [16], cvvLengths: [3], perBrandLengths: [:])
/// ```
/// `SecureFieldsManager.scheduleBinLookup` has no way to distinguish "the server told us nothing
/// matched" from "we couldn't even parse the response" — both look identical, and neither is ever
/// surfaced to the host app via `secureFieldsDidFail`.
final class Bug13FakeSuccessViewController: BugBaseViewController {

    // Real, Luhn-valid 15-digit Amex test PAN.
    private let amexPAN = "378282246310005"

    private let manager = BugSecureFieldsFactory.make(brands: [.amex])
    private let eventLog = EventLogView()
    private var debugLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Bug #13"
        MockScenarios.reset()
        // Deliberately not valid JSON — this is what should surface as a parsing/decoding error.
        MockURLProtocol.handlers["bin-lookup"] = .init(data: Data("{ ceci n'est pas du JSON valide".utf8), statusCode: 200)
        manager.delegate = self

        addHeader(
            number: 13,
            title: "Un BIN lookup illisible se transforme en faux succès [16]/[3]",
            steps: [
                "Le serveur BIN mocké renvoie ici un corps 200 OK volontairement invalide (pas du JSON du tout).",
                "Tapez « Remplir un PAN Amex 15 chiffres » : un vrai numéro de test Amex, Luhn-correct, 15 chiffres.",
                "Regardez le journal : aucun secureFieldsDidFail n'est jamais journalisé, alors que le lookup a pourtant échoué à l'analyse.",
                "Regardez le panneau Debug : le champ PAN reste invalide silencieusement, sans qu'aucune explication ne soit jamais donnée à l'app hôte.",
            ],
            expected: "Une réponse BIN illisible doit être traitée comme une erreur (par exemple secureFieldsDidFail(.invalidResponse)), pas comme un succès. À défaut d'information fiable, le champ ne devrait pas rester bloqué sur une longueur [16] arbitraire pour une carte Amex 15 chiffres.",
            observed: "`(try? JSONDecoder().decode(BinLookupResponse.self, from: data))?.toBinLookupResult() ?? BinLookupResult(brands: [], panLengths: [16], cvvLengths: [3], perBrandLengths: [:])` remplace tout échec de parsing par un succès fabriqué. panField.validLengths reste donc à [16] : le PAN Amex de 15 chiffres, pourtant Luhn-valide, n'est jamais reconnu comme valide, et rien ne prévient jamais l'app hôte (pas de secureFieldsDidFail, pas de secureFieldsBrandsDetected non plus puisque brands est vide)."
        )

        stackView.addArrangedSubview(sectionLabel("Numéro de carte (Amex, 15 chiffres)"))
        stackView.addArrangedSubview(manager.panContainer)

        stackView.addArrangedSubview(makeButton("Remplir un PAN Amex 15 chiffres (\(amexPAN))", action: #selector(fillPAN)))
        stackView.addArrangedSubview(makeTintedButton("Réinitialiser", action: #selector(resetDemo)))

        debugLabel = addDebugPanel(title: "Debug")
        stackView.addArrangedSubview(sectionLabel("Journal des callbacks du délégué"))
        stackView.addArrangedSubview(eventLog)

        refreshDebugPanel()
    }

    @objc private func fillPAN() {
        guard let panField = manager.panContainer.firstTextField() else { return }
        eventLog.log("(script) saisie du PAN Amex 15 chiffres")
        panField.simulateTyping(amexPAN)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.refreshDebugPanel() }
    }

    @objc private func resetDemo() {
        eventLog.clear()
        manager.clearFields()
        refreshDebugPanel()
    }

    private func refreshDebugPanel() {
        debugLabel.text = """
        PAN saisi (chiffres)        = \(manager.panDigitCount)
        manager.isFieldValid(.pan)  = \(manager.isFieldValid(.pan) ? "✓" : "✗ (BUG : Amex 15 chiffres, Luhn-valide, refusé sans explication)")

        Le corps HTTP mocké était illisible (pas du JSON) — pourtant le SDK a traité le lookup
        comme un succès silencieux (panLengths=[16], cvvLengths=[3], brands=[]).
        """
    }
}

extension Bug13FakeSuccessViewController: SecureFieldsDelegate {
    func secureFieldsContentChanged() { refreshDebugPanel() }
    func secureFieldsFormValidityChanged(_ isValid: Bool) { refreshDebugPanel() }
    func secureFieldsBrandsDetected(_ brands: [CardBrand]) {
        eventLog.log("secureFieldsBrandsDetected(\(brands.map(\.rawValue))) — vide, alors que le lookup a pourtant \"réussi\"")
    }
    func secureFieldsDidFail(_ error: SecureFieldsError) {
        eventLog.log("secureFieldsDidFail(\(error)) ← ne se produit jamais dans ce scénario : c'est justement le bug")
    }
}
#endif
