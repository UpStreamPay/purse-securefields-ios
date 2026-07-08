#if DEBUG
import UIKit
import PurseSecureFields

/// Bug #1 — `CardValidator.isExpiryValid(month:year:)` (Sources/PurseSecureFields/Internal/CardValidator.swift)
/// compares the parsed expiry year against `Calendar.current.component(.year, from: Date())`.
/// The parsed year is *always* Gregorian (`2000 + YY`, see `SecureExpDateField.parsedExpiry`),
/// but `Calendar.current` follows whatever calendar the device's Region setting uses. On a
/// Buddhist, Japanese or Hijri calendar, `Calendar.current`'s year component is not the Gregorian
/// year, so the comparison silently breaks: a genuinely future expiry date is judged expired.
final class Bug01ExpiryCalendarViewController: BugBaseViewController {

    private let manager = BugSecureFieldsFactory.make()
    private var debugLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Bug #1"
        MockScenarios.reset()
        manager.delegate = self

        addHeader(
            number: 1,
            title: "Année d'expiration comparée avec le mauvais calendrier",
            steps: [
                "Sur l'appareil : Réglages > Général > Langue et région > Calendrier > Bouddhiste (ou Japonais / Hégire).",
                "Revenez sur cet écran, ou repassez simplement l'app au premier plan.",
                "Dans le champ « Expiration », saisissez 12/28 (décembre 2028 — une date clairement future).",
            ],
            expected: "Le champ expiration est valide : 12/2028 est dans le futur, quel que soit le calendrier affiché par l'appareil.",
            observed: "Le champ reste invalide indéfiniment, car isExpiryValid compare l'année « 2028 » (toujours grégorienne, calculée en dur comme 2000+YY) à Calendar.current.component(.year, from: Date()), qui vaut ~2571 sous un calendrier bouddhiste. Comme 2028 < 2571, la date est jugée expirée.",
            limitation: "Changer le calendrier système passe par l'app Réglages."
        )

        stackView.addArrangedSubview(sectionLabel("Expiration (champ réel du SDK)"))
        stackView.addArrangedSubview(fieldContainer(manager.expDateView))

        debugLabel = addDebugPanel(title: "Debug — validité en direct")

        refreshDebugPanel()

        NotificationCenter.default.addObserver(self, selector: #selector(refreshDebugPanel),
                                                name: NSLocale.currentLocaleDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshDebugPanel),
                                                name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    @objc private func refreshDebugPanel() {
        debugLabel.text = """
        manager.isFieldValid(.expDate)    = \(manager.isFieldValid(.expDate) ? "✓" : "✗")
        manager.hasFieldContent(.expDate) = \(manager.hasFieldContent(.expDate) ? "✓" : "✗")
        """
    }
}

extension Bug01ExpiryCalendarViewController: SecureFieldsDelegate {
    func secureFieldsContentChanged() { refreshDebugPanel() }
    func secureFieldsFormValidityChanged(_ isValid: Bool) { refreshDebugPanel() }
}
#endif
