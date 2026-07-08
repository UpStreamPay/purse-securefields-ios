#if DEBUG
import UIKit
import PurseSecureFields

/// Bug #3 — `SecureCVVField.applyBirthdate(from:)` (Views/SecureCVVField.swift:63-69) formats the
/// birth date with a plain `DateFormatter()`, using `dateFormat = "yyyy-MM-dd"` but never setting
/// `.locale` or `.calendar`. A `DateFormatter` without an explicit locale/calendar falls back to
/// the device's current locale and calendar — so on a device set to a non-Gregorian calendar
/// (Buddhist, Japanese, Hijri...) the "yyyy" component is not the Gregorian year, even though the
/// format string looks like an ISO-8601 date. The wrong string is sent as `birth_date` in the
/// tokenization payload.
final class Bug03BirthDateLocaleViewController: BugBaseViewController {

    // 19-digit, Luhn-valid PAN used only to trigger Oney mode (fictitious BIN).
    private let oneyPAN = "6000000000000000004"

    private let manager = BugSecureFieldsFactory.make(brands: [.oney])
    private var payloadLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Bug #3"
        MockScenarios.reset()
        MockScenarios.setBinLookup([MockBinBrand(.oney, isMain: true, panLengths: [19])])
        MockScenarios.setTokenizeSuccess()
        manager.delegate = self

        addHeader(
            number: 3,
            title: "birth_date formaté sans locale/calendrier fixes",
            steps: [
                "Tapez « Remplir carte Oney » pour saisir un PAN Oney, une expiration valide et sélectionner le mode date de naissance.",
                "Tapez « Choisir une date puis envoyer » : ouvre le picker, sélectionne une date fixe puis simule un submit().",
                "Regardez « Payload de tokenisation intercepté » ci-dessous : c'est exactement l'octet envoyé au serveur (capturé via MockURLProtocol).",
                "Pour le vrai bug : Réglages > Général > Langue et région > Calendrier > Bouddhiste, puis relancez l'étape 2 — le birth_date envoyé devient « 25xx-… » au lieu de « 20xx-… ».",
            ],
            expected: "birth_date doit toujours être une date grégorienne au format ISO-8601 (yyyy-MM-dd), quel que soit le calendrier réglé sur l'appareil — un serveur de vérification d'âge ne doit jamais recevoir une année bouddhiste/japonaise/hégire.",
            observed: "DateFormatter() est construit sans locale ni calendar : il hérite du calendrier système. Sous calendrier bouddhiste, birth_date envoyé porte une année clairement fausse (~+543 ans).",
            limitation: "Changer le calendrier système passe par l'app Réglages. Le panneau « Payload intercepté » montre la valeur réelle envoyée par le SDK sur cet appareil, avec le calendrier actuellement réglé."
        )

        stackView.addArrangedSubview(sectionLabel("Numéro de carte (Oney)"))
        stackView.addArrangedSubview(manager.panContainer)

        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 12
        row.distribution = .fillEqually
        let cvvStack = UIStackView()
        cvvStack.axis = .vertical
        cvvStack.spacing = 6
        cvvStack.addArrangedSubview(sectionLabel("Date de naissance"))
        cvvStack.addArrangedSubview(fieldContainer(manager.cvvView))
        let expStack = UIStackView()
        expStack.axis = .vertical
        expStack.spacing = 6
        expStack.addArrangedSubview(sectionLabel("Expiration"))
        expStack.addArrangedSubview(fieldContainer(manager.expDateView))
        row.addArrangedSubview(cvvStack)
        row.addArrangedSubview(expStack)
        stackView.addArrangedSubview(row)

        stackView.addArrangedSubview(makeButton("1. Remplir carte Oney (PAN + expiration)", action: #selector(fillCard)))
        stackView.addArrangedSubview(makeButton("2. Envoyer (submit) et intercepter le payload", action: #selector(submitAndCapture)))

        stackView.addArrangedSubview(sectionLabel("Payload de tokenisation intercepté (réel, cet appareil)"))
        payloadLabel = UILabel()
        payloadLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        payloadLabel.numberOfLines = 0
        payloadLabel.text = "(pas encore de submit)"
        stackView.addArrangedSubview(panel(payloadLabel))
    }

    @objc private func fillCard() {
        guard let panField = manager.panContainer.firstTextField() else { return }
        panField.simulateTyping(oneyPAN)
        // Give the debounced BIN lookup (300ms) time to resolve and flip the CVV field into
        // birthdate mode before we fill the expiry date.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, let expField = self.manager.expDateView.firstTextField() else { return }
            expField.simulateTyping("1230")
        }
    }

    @objc private func submitAndCapture() {
        payloadLabel.text = "Envoi en cours…"
        manager.submit()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.refreshPayloadLabel()
        }
    }

    private func refreshPayloadLabel() {
        guard let pretty = MockScenarios.prettyPrintedLastTokenizePayload() else {
            payloadLabel.text = "(aucun payload capturé — le submit a-t-il réussi ? le formulaire était-il valide ?)"
            return
        }
        payloadLabel.text = pretty
    }
}

extension Bug03BirthDateLocaleViewController: SecureFieldsDelegate {
    func secureFieldsDidTokenize(_ result: TokenizationResult) { refreshPayloadLabel() }
    func secureFieldsDidFail(_ error: SecureFieldsError) {
        payloadLabel.text = "Échec du submit — voir le formulaire (PAN/expiration/date renseignés ?)."
    }
}
#endif
