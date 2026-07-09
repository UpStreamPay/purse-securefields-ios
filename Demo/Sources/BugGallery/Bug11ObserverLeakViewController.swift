#if DEBUG
import UIKit
import PurseSecureFields

/// Bug #11 — `SecureFieldsManager.setupPrivacyObservers()` (SecureFieldsManager.swift ~line 253)
/// registers 4 block-based `NotificationCenter` observers (`willResignActive`, `didBecomeActive`,
/// `UIScreen.capturedDidChangeNotification`, `userDidTakeScreenshotNotification`) and stores their
/// tokens in the private `privacyObservers` array. `deinit` (SecureFieldsManager.swift ~line
/// 139-142) only cleans up `monitoringObservers` — it never does
/// `privacyObservers.forEach { NotificationCenter.default.removeObserver($0) }`. Every
/// `SecureFieldsManager` a host app creates and releases (e.g. leaving/re-entering a checkout
/// screen) leaves 4 block registrations behind that `NotificationCenter` keeps invoking forever.
final class Bug11ObserverLeakViewController: BugBaseViewController {

    private var weakManagerBoxes: [() -> SecureFieldsManager?] = []

    /// Stand-in for one of the SDK's 4 leaked `privacyObservers` tokens. `privacyObservers` is a
    /// *private* property of `SecureFieldsManager`, so the host app cannot enumerate the SDK's
    /// actual leaked tokens from here. This probe registers itself the exact same way — the same
    /// public `NotificationCenter.addObserver(forName:object:queue:using:)` API, on one of the
    /// same 4 notifications — every time a manager below is created, and — mirroring the real bug
    /// — is never removed either. It lets us prove the *mechanism* (a block keeps firing forever,
    /// once per manager ever created, long after that manager is gone) with real numbers.
    private var shadowProbeTokens: [NSObjectProtocol] = []
    private var shadowProbeFireCount = 0

    private let eventLog = EventLogView()
    private var debugLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Bug #11"
        MockScenarios.reset()

        addHeader(
            number: 11,
            title: "Observateurs NotificationCenter jamais retirés (setupPrivacyObservers)",
            steps: [
                "Tapez « Créer puis libérer 10 managers » : 10 vrais SecureFieldsManager sont instanciés puis relâchés immédiatement (aucune référence forte conservée après la boucle).",
                "Regardez « Managers encore vivants » ci-dessous : il doit retomber à 0 — ARC libère bien chaque manager, ce n'est donc PAS un cycle de rétention classique.",
                "Tapez « Poster didBecomeActiveNotification » : ce post correspond exactement à ce qui se produit chaque fois que l'app repasse au premier plan.",
                "Regardez « Déclenchements cumulés de la sonde » : il augmente de +10 à chaque post, alors que les 10 managers d'origine sont déjà désalloués depuis longtemps.",
            ],
            expected: "deinit doit retirer les 4 observateurs enregistrés par setupPrivacyObservers() (exactement comme il le fait déjà pour monitoringObservers), pour que le nombre de blocs vivants dans NotificationCenter n'augmente pas indéfiniment avec chaque manager créé.",
            observed: "SecureFieldsManager.deinit ne nettoie que monitoringObservers ; privacyObservers n'est jamais passé à NotificationCenter.default.removeObserver(_:). Chaque manager créé puis libéré laisse 4 blocs enregistrés pour de bon. Ils ne provoquent ni crash ni effet visible immédiat (ils capturent [weak self], donc s'exécutent en no-op une fois le manager désalloué) — mais ils restent en mémoire et sont ré-exécutés à chaque notification système, pour toujours, pendant toute la durée de vie du process.",
            limitation: "NotificationCenter n'expose aucune API publique pour énumérer ou compter ses observateurs, et privacyObservers est une propriété privée du SDK : impossible de lire directement « combien de blocs de la fuite réelle restent enregistrés ». La sonde ci-dessous reproduit le même mécanisme (même API publique, même notification, jamais retirée) pour rendre le phénomène mesurable, plutôt que de compter la fuite réelle directement."
        )

        stackView.addArrangedSubview(makeButton("Créer puis libérer 10 managers", action: #selector(createAndReleaseTen)))
        stackView.addArrangedSubview(makeButton("Poster didBecomeActiveNotification", action: #selector(postNotification)))
        stackView.addArrangedSubview(makeTintedButton("Réinitialiser", action: #selector(resetDemo)))

        debugLabel = addDebugPanel(title: "Debug — comptage")
        stackView.addArrangedSubview(sectionLabel("Journal"))
        stackView.addArrangedSubview(eventLog)

        refreshDebugPanel()
    }

    @objc private func createAndReleaseTen() {
        for i in 0..<10 {
            autoreleasepool {
                let manager = BugSecureFieldsFactory.make()
                weak var weakRef = manager
                weakManagerBoxes.append({ weakRef })

                let token = NotificationCenter.default.addObserver(
                    forName: UIApplication.didBecomeActiveNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in self?.shadowProbeFireCount += 1 }
                shadowProbeTokens.append(token)

                eventLog.log("(script) manager #\(i + 1) créé, puis relâché en sortie de bloc")
            }
        }
        eventLog.log("(script) 10 managers créés et relâchés — leurs 4×10 = 40 observateurs privacyObservers réels ne sont, eux, jamais retirés")
        refreshDebugPanel()
    }

    @objc private func postNotification() {
        eventLog.log("(test) post manuel de UIApplication.didBecomeActiveNotification")
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.refreshDebugPanel() }
    }

    @objc private func resetDemo() {
        shadowProbeTokens.forEach { NotificationCenter.default.removeObserver($0) }
        shadowProbeTokens = []
        shadowProbeFireCount = 0
        weakManagerBoxes = []
        eventLog.clear()
        refreshDebugPanel()
    }

    private func refreshDebugPanel() {
        let alive = weakManagerBoxes.filter { $0() != nil }.count
        debugLabel.text = """
        Managers créés puis libérés                    = \(weakManagerBoxes.count)
        Managers encore vivants (fuite d'objet ?)       = \(alive)  (attendu : 0 — pas de retain cycle)
        Sondes "shadow" enregistrées (jamais retirées)  = \(shadowProbeTokens.count)
        Déclenchements cumulés de la sonde après un post = \(shadowProbeFireCount)

        \(shadowProbeTokens.isEmpty ? "Tapez « Créer puis libérer 10 managers » pour commencer." : "Chaque post ajoute +\(shadowProbeTokens.count) déclenchements, pour toujours — alors qu'aucun des 10 managers/contrôleurs d'origine n'existe plus.")
        """
    }
}
#endif
