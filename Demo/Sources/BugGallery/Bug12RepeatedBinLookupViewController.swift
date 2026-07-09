#if DEBUG
import UIKit
import PurseSecureFields

/// Bug #12 — `SecureFieldsManager.scheduleBinLookup(digits:)` (SecureFieldsManager.swift ~line
/// 216) skips a redundant fetch with `if prefix == lastBinPrefix && !detectedBrands.isEmpty {
/// return }`. When a BIN lookup *succeeds* but resolves to zero usable brands — a scheme
/// `CardBrand` doesn't map (see Bug #16), or every returned brand gets filtered out by
/// `config.brands` — `detectedBrands` stays `[]`. The `!detectedBrands.isEmpty` half of that guard
/// is then always false, so the "same prefix, don't refetch" short-circuit never engages: a
/// brand-new network request fires after every single keystroke past 6 digits, even once the
/// 8-digit prefix `scheduleBinLookup` actually keys on has stopped changing.
final class Bug12RepeatedBinLookupViewController: BugBaseViewController {

    // 12 digits so we keep typing well past the 8-digit prefix the SDK keys on.
    private let digits = "400000123456"

    private let manager = BugSecureFieldsFactory.make(brands: [.visa])
    private let eventLog = EventLogView()
    private var debugLabel: UILabel!
    private var requestCount = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Bug #12"
        MockScenarios.reset()
        // "JCB" is not a CardBrand case: BinLookupResponse.toBinLookupResult() silently drops it
        // (compactMap over CardBrand(rawValue:)), so `allowed` — and therefore `detectedBrands` —
        // stays empty after every single "successful" lookup, no matter how many times we ask.
        MockURLProtocol.handlers["bin-lookup"] = .init(
            data: Data(#"{"brands":[{"brand":"JCB","is_main":true,"pan_lengths":[16],"cvv_lengths":[3]}]}"#.utf8),
            statusCode: 200
        )
        MockURLProtocol.onRequest = { [weak self] key, _ in
            guard key == "bin-lookup" else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.requestCount += 1
                self.eventLog.log("→ POST bin-lookup  (requête n°\(self.requestCount))")
                self.refreshDebugPanel()
            }
        }
        manager.delegate = self

        addHeader(
            number: 12,
            title: "Un lookup BIN relancé à chaque frappe quand aucune marque n'est retenue",
            steps: [
                "Le BIN mocké renvoie toujours la marque \"JCB\", absente de CardBrand : detectedBrands reste donc vide après CHAQUE lookup pourtant réussi.",
                "Tapez « Simuler la saisie 6 → 12 chiffres (avec pauses) » : les chiffres sont tapés un par un avec 400 ms de pause, laissant le debounce de 300 ms se déclencher entre chaque frappe.",
                "Regardez le compteur de requêtes ci-dessous : il augmente à CHAQUE frappe, y compris à partir du 9ᵉ chiffre alors que le préfixe de 8 chiffres sur lequel se base le SDK ne change plus.",
            ],
            expected: "Une fois un préfixe de 8 chiffres déjà résolu (même à 0 marque autorisée), retaper des chiffres supplémentaires qui ne changent pas ce préfixe ne doit déclencher aucune nouvelle requête BIN.",
            observed: "Le guard `prefix == lastBinPrefix && !detectedBrands.isEmpty` exige aussi que detectedBrands soit non vide pour sauter le lookup. Si le lookup réussit mais ne retient aucune marque (marque hors config, ou schéma non mappé comme ici), detectedBrands reste [] pour toujours : la condition n'est donc jamais vraie, et un lookup BIN identique repart à chaque frappe, même quand le préfixe de 8 chiffres est rigoureusement inchangé."
        )

        stackView.addArrangedSubview(sectionLabel("Numéro de carte"))
        stackView.addArrangedSubview(manager.panContainer)

        stackView.addArrangedSubview(makeButton("Simuler la saisie 6 → 12 chiffres (avec pauses)", action: #selector(runTimedTyping)))
        stackView.addArrangedSubview(makeTintedButton("Réinitialiser", action: #selector(resetDemo)))

        debugLabel = addDebugPanel(title: "Compteur de requêtes BIN")
        stackView.addArrangedSubview(sectionLabel("Journal réseau"))
        stackView.addArrangedSubview(eventLog)

        refreshDebugPanel()
    }

    @objc private func runTimedTyping() {
        guard let panField = manager.panContainer.firstTextField() else { return }
        eventLog.log("(script) début de la saisie chiffre par chiffre, pause 400 ms")
        panField.simulateTypingWithDelay(digits, delay: 0.4, onEachCharacter: { [weak self] current in
            guard current.count >= 6 else { return }
            self?.eventLog.log("(script) frappe → \(current.count) chiffre(s), préfixe utilisé par le SDK = \(String(current.prefix(8)))")
        })
    }

    @objc private func resetDemo() {
        requestCount = 0
        eventLog.clear()
        manager.clearFields()
        refreshDebugPanel()
    }

    private func refreshDebugPanel() {
        debugLabel.text = """
        Chiffres tapés               = \(manager.panDigitCount)
        Requêtes BIN envoyées        = \(requestCount)
        Marques détectées            = aucune (JCB n'est mappé à aucun CardBrand)

        Attendu (sans le bug) : 3 requêtes au plus (une par préfixe distinct de 6, 7 puis 8 chiffres) ;
        au-delà de 8 chiffres le préfixe ne change plus, donc plus aucune requête ne devrait partir.
        Observé : une nouvelle requête part à CHAQUE frappe, y compris de 9 à 12 chiffres.
        """
    }
}

extension Bug12RepeatedBinLookupViewController: SecureFieldsDelegate {
    func secureFieldsBrandsDetected(_ brands: [CardBrand]) { refreshDebugPanel() }
}
#endif
