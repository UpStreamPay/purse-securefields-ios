import Foundation
import Testing
import UIKit
@testable import PurseSecureFields

/// `SecureFieldsConfig.brandSelector` and the `submit(selectedNetwork:)` override
/// (SDK-12108, gap 11): a merchant must be able to keep the cardholder from arbitrating the
/// network of a co-badged card — and, when the selector is off, to name that network itself.
@MainActor
struct BrandSelectorConfigTests {

    // MARK: - Selector visibility

    @Test func selectorStaysHiddenWhenDisabled() {
        let view = SecureBrandSelectorView()
        view.isSelectorEnabled = false

        view.update(brands: [.carteBancaire, .visa])

        #expect(view.isHidden)
        // Resolution still runs — the submitted network depends on it.
        #expect(view.selectedBrand == .carteBancaire)
    }

    @Test func selectorIsVisibleWhenEnabledAndBrandsExist() {
        let view = SecureBrandSelectorView()
        view.isSelectorEnabled = true

        view.update(brands: [.carteBancaire, .visa])

        #expect(!view.isHidden)
        #expect(view.selectedBrand == .carteBancaire)
    }

    @Test func selectorIsHiddenWithoutBrandsEvenWhenEnabled() {
        let view = SecureBrandSelectorView()
        view.isSelectorEnabled = true

        view.update(brands: [])

        #expect(view.isHidden)
    }

    @Test func managerAppliesConfigFlagToTheSelector() {
        let hidden = SecureFieldsManager(config: .init(tenantId: "t", monitoringEnabled: false))
        let shown = SecureFieldsManager(
            config: .init(tenantId: "t", brandSelector: true, monitoringEnabled: false)
        )

        func selector(_ m: SecureFieldsManager) -> SecureBrandSelectorView {
            m.panContainer.subviews.compactMap { $0 as? SecureBrandSelectorView }.first!
        }

        #expect(selector(hidden).isSelectorEnabled == false, "brandSelector defaults to false")
        #expect(selector(shown).isSelectorEnabled == true)
    }

    // MARK: - submit(selectedNetwork:)

    @Test func requestedNetworkIsSubmittedWhenSelectorIsDisabled() {
        let effective = SecureFieldsManager.effectiveNetwork(
            requested: .visa,
            resolved: .carteBancaire,
            detected: [.carteBancaire, .visa],
            brandSelectorEnabled: false
        )
        #expect(effective == .visa)
    }

    @Test func requestedNetworkIsIgnoredWhenSelectorIsEnabled() {
        let effective = SecureFieldsManager.effectiveNetwork(
            requested: .visa,
            resolved: .carteBancaire,
            detected: [.carteBancaire, .visa],
            brandSelectorEnabled: true
        )
        #expect(effective == .carteBancaire, "the cardholder's pick outranks the merchant's")
    }

    @Test func undetectedRequestedNetworkIsRefused() {
        let effective = SecureFieldsManager.effectiveNetwork(
            requested: .amex,
            resolved: .visa,
            detected: [.visa],
            brandSelectorEnabled: false
        )
        #expect(effective == .visa, "never tokenize under a network the BIN doesn't carry")
    }

    @Test func resolvedNetworkIsKeptWhenNoneRequested() {
        let effective = SecureFieldsManager.effectiveNetwork(
            requested: nil,
            resolved: .mastercard,
            detected: [.mastercard],
            brandSelectorEnabled: false
        )
        #expect(effective == .mastercard)
    }
}
