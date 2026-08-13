import Testing
import UIKit
@testable import PurseSecureFields

@MainActor
struct SecureBrandSelectorViewTests {

    private func chips(in view: UIView) -> [UIControl] {
        view.subviews.flatMap { sub -> [UIControl] in
            var found = chips(in: sub)
            if let control = sub as? UIControl { found.insert(control, at: 0) }
            return found
        }
    }

    @Test func chipsAreAccessibleButtonsWithStableIdentifiers() {
        let view = SecureBrandSelectorView()
        view.update(brands: [.visa, .carteBancaire])

        let found = chips(in: view)
        #expect(found.count == 2)
        #expect(found.allSatisfy { $0.isAccessibilityElement })
        #expect(found.allSatisfy { $0.accessibilityTraits.contains(.button) })
        #expect(found.map(\.accessibilityIdentifier) == ["brand_chip_visa", "brand_chip_carte_bancaire"])
        #expect(found.map(\.accessibilityLabel) == ["Visa", "Cartes Bancaires"])
    }

    @Test func selectedChipCarriesSelectedTrait() {
        let view = SecureBrandSelectorView()
        view.update(brands: [.visa, .mastercard])

        let found = chips(in: view)
        #expect(found[0].accessibilityTraits.contains(.selected)) // default selection = first
        #expect(!found[1].accessibilityTraits.contains(.selected))
    }

    @Test func identifiersSurviveRebuild() {
        let view = SecureBrandSelectorView()
        view.update(brands: [.visa, .mastercard])
        view.update(brands: [.mastercard]) // chips are destroyed and rebuilt on every BIN lookup

        let found = chips(in: view)
        #expect(found.map(\.accessibilityIdentifier) == ["brand_chip_mastercard"])
    }

    @Test func selectorViewHasIdentifier() {
        #expect(SecureBrandSelectorView().accessibilityIdentifier == "brand_selector")
    }
}
