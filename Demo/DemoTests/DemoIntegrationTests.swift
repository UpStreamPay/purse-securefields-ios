import Testing
import UIKit
import PurseSecureFields

@MainActor
struct DemoIntegrationTests {

    private func makeManager() -> SecureFieldsManager {
        SecureFieldsManager(config: SecureFieldsConfig(
            tenantId: "test-tenant",
            baseURL: "https://api.example.com"
        ))
    }

    // MARK: Init

    @Test func managerInitializesWithNoValidity() {
        let manager = makeManager()
        #expect(!manager.isFieldValid(.pan))
        #expect(!manager.isFieldValid(.cvv))
        #expect(!manager.isFieldValid(.expDate))
        #expect(!manager.isFieldValid(.holderName))
    }

    @Test func panDigitCountStartsAtZero() {
        let manager = makeManager()
        #expect(manager.panDigitCount == 0)
    }

    @Test func hasFieldContentFalseOnInit() {
        let manager = makeManager()
        #expect(!manager.hasFieldContent(.pan))
        #expect(!manager.hasFieldContent(.cvv))
        #expect(!manager.hasFieldContent(.expDate))
        #expect(!manager.hasFieldContent(.holderName))
    }

    // MARK: Views

    @Test func viewsAreUIViewInstances() {
        let manager = makeManager()
        #expect(manager.cvvView is UIView)
        #expect(manager.expDateView is UIView)
        #expect(manager.holderNameView is UIView)
    }

    @Test func panContainerIsUIView() {
        let manager = makeManager()
        #expect(manager.panContainer is UIView)
    }

    @Test func viewsAreDistinctObjects() {
        let manager = makeManager()
        #expect(manager.cvvView !== manager.expDateView)
        #expect(manager.cvvView !== manager.holderNameView)
        #expect(manager.expDateView !== manager.holderNameView)
    }

    // MARK: clearFields

    @Test func clearFieldsResetsAllValidity() {
        let manager = makeManager()
        manager.clearFields()
        #expect(!manager.isFieldValid(.pan))
        #expect(!manager.isFieldValid(.cvv))
        #expect(!manager.isFieldValid(.expDate))
        #expect(!manager.isFieldValid(.holderName))
    }

    @Test func clearFieldsResetsPanDigitCount() {
        let manager = makeManager()
        manager.clearFields()
        #expect(manager.panDigitCount == 0)
    }

    @Test func clearFieldsResetsHasContent() {
        let manager = makeManager()
        manager.clearFields()
        #expect(!manager.hasFieldContent(.pan))
        #expect(!manager.hasFieldContent(.cvv))
        #expect(!manager.hasFieldContent(.expDate))
        #expect(!manager.hasFieldContent(.holderName))
    }

    // MARK: Config

    @Test func configWithCustomStyle() {
        let style = SecureFieldsStyle(font: .boldSystemFont(ofSize: 18), textColor: .red)
        let config = SecureFieldsConfig(
            tenantId: "tenant",
            baseURL: "https://api.example.com",
            style: style
        )
        let manager = SecureFieldsManager(config: config)
        _ = manager // init does not crash
    }

    @Test func configWithCustomPlaceholders() {
        let placeholders = SecureFieldsPlaceholders(
            pan: "0000 0000 0000 0000",
            cvv: "000",
            expDate: "MM/YY",
            holderName: "Full Name"
        )
        let config = SecureFieldsConfig(
            tenantId: "tenant",
            baseURL: "https://api.example.com",
            placeholders: placeholders
        )
        let manager = SecureFieldsManager(config: config)
        _ = manager
    }

    @Test func configWithSelectedBrands() {
        let config = SecureFieldsConfig(
            tenantId: "tenant",
            baseURL: "https://api.example.com",
            brands: [.visa, .mastercard]
        )
        #expect(config.brands == [.visa, .mastercard])
    }

    @Test func configDefaultsToAllBrands() {
        let config = SecureFieldsConfig(
            tenantId: "tenant",
            baseURL: "https://api.example.com"
        )
        #expect(config.brands == CardBrand.allCases)
    }

    // MARK: Delegate

    @Test func delegateCanBeSetAndCleared() {
        let manager = makeManager()
        let delegate = MockDelegate()
        manager.delegate = delegate
        #expect(manager.delegate != nil)
        manager.delegate = nil
        #expect(manager.delegate == nil)
    }
}

private final class MockDelegate: SecureFieldsDelegate {
    func secureFieldsDidTokenize(_ result: TokenizationResult) {}
    func secureFieldsDidFail(_ error: SecureFieldsError) {}
    func secureFieldsBrandsDetected(_ brands: [CardBrand]) {}
    func secureFieldsFormValidityChanged(_ isValid: Bool) {}
}
