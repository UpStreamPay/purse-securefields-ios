#if DEBUG
import UIKit

/// Describes one entry in the bug gallery home screen.
struct BugInfo {
    let number: Int
    let title: String
    let subtitle: String
    let makeViewController: () -> UIViewController
}

enum BugCatalog {
    static let all: [BugInfo] = [
        BugInfo(number: 1,
                title: "Année d'expiration vs calendrier système",
                subtitle: "CardValidator.isExpiryValid utilise Calendar.current",
                makeViewController: { Bug01ExpiryCalendarViewController() }),
        BugInfo(number: 2,
                title: "Longueur PAN Oney ignorée",
                subtitle: "validLengths reste [16] même quand Oney (19) est sélectionné",
                makeViewController: { Bug02OneyLengthViewController() }),
        BugInfo(number: 3,
                title: "birth_date sans locale/calendrier fixes",
                subtitle: "Le payload Oney peut envoyer une année non grégorienne",
                makeViewController: { Bug03BirthDateLocaleViewController() }),
        BugInfo(number: 4,
                title: "Date de naissance pré-remplie à Aujourd'hui",
                subtitle: "Le champ CVV/Oney devient valide sans aucune saisie",
                makeViewController: { Bug04BirthDatePrefillViewController() }),
        BugInfo(number: 5,
                title: "Marque envoyée arbitraire au submit",
                subtitle: "selected_network = VISA même pour une Mastercard",
                makeViewController: { Bug05NetworkFallbackViewController() }),
        BugInfo(number: 6,
                title: "Curseur PAN forcé en fin de champ",
                subtitle: "Impossible d'éditer au milieu du numéro de carte",
                makeViewController: { Bug06CursorJumpViewController() }),
        BugInfo(number: 7,
                title: "Changement de marque sans invalidation du formulaire",
                subtitle: "Le CVV est vidé mais formValidityChanged(false) n'est jamais émis",
                makeViewController: { Bug07MissingInvalidationViewController() }),
        BugInfo(number: 8,
                title: "Sélection de marque écrasée par un re-lookup",
                subtitle: "Le choix manuel de l'utilisateur est silencieusement annulé",
                makeViewController: { Bug08BrandOverrideViewController() }),
        BugInfo(number: 9,
                title: "État résiduel après tokenisation",
                subtitle: "Le CVV reste en mode date de naissance après un submit réussi",
                makeViewController: { Bug09StaleStateViewController() }),
        BugInfo(number: 10,
                title: "formValidityChanged émis en boucle",
                subtitle: "Le contrat « seulement au changement » n'est pas respecté",
                makeViewController: { Bug10DuplicateEventsViewController() }),
    ]
}
#endif
