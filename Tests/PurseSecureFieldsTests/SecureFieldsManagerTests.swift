import Foundation
import Testing
import UIKit
@testable import PurseSecureFields

/// Fails every request immediately — keeps manager-level tests fully offline while still
/// exercising the BIN-lookup failure path.
private final class FailingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

private final class SpyDelegate: SecureFieldsDelegate {
    var failures: [SecureFieldsError] = []
    var brandsDetected: [[CardBrand]] = []
    var validityChanges: [Bool] = []
    var binLookupFailures: [SecureFieldsError] = []

    func secureFieldsDidTokenize(_ result: TokenizationResult) {}
    func secureFieldsDidFail(_ error: SecureFieldsError) { failures.append(error) }
    func secureFieldsBrandsDetected(_ brands: [CardBrand]) { brandsDetected.append(brands) }
    func secureFieldsFormValidityChanged(_ isValid: Bool) { validityChanges.append(isValid) }
    func secureFieldsBinLookupFailed(_ error: SecureFieldsError) { binLookupFailures.append(error) }
}

@MainActor
struct SecureFieldsManagerTests {

    private func makeManager(
        requiresHolderName: Bool = false,
        fields: SecureFieldsFieldsConfig = .all
    ) -> SecureFieldsManager {
        var config = SecureFieldsConfig(
            tenantId: "tenant",
            fields: fields,
            requiresHolderName: requiresHolderName,
            monitoringEnabled: false
        )
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [FailingURLProtocol.self]
        config.urlSessionOverride = URLSession(configuration: sessionConfig)
        return SecureFieldsManager(config: config)
    }

    private func cvvField(_ m: SecureFieldsManager) -> SecureCVVField { m.cvvView as! SecureCVVField }
    private func expField(_ m: SecureFieldsManager) -> SecureExpDateField { m.expDateView as! SecureExpDateField }
    private func holderField(_ m: SecureFieldsManager) -> SecureHolderNameField { m.holderNameView as! SecureHolderNameField }
    private func panField(_ m: SecureFieldsManager) -> SecurePANField {
        m.panContainer.subviews.compactMap { $0 as? SecurePANField }.first!
    }

    private func type(_ text: String, into field: SecureBaseField) {
        field.text = text
        field.textDidChange()
    }

    // MARK: allowedBrands ordering

    @Test func allowedBrandsFollowConfigOrder() {
        // The API answered [visa, carteBancaire]; the merchant prefers CB first.
        let allowed = SecureFieldsManager.allowedBrands(
            api: [.visa, .carteBancaire],
            config: [.carteBancaire, .visa, .mastercard]
        )
        #expect(allowed == [.carteBancaire, .visa])
    }

    @Test func allowedBrandsFiltersToConfig() {
        let allowed = SecureFieldsManager.allowedBrands(
            api: [.visa, .maestro],
            config: [.visa]
        )
        #expect(allowed == [.visa])
    }

    // MARK: expectedLengths

    @Test func expectedLengthsDefaults() {
        let manager = makeManager()
        #expect(manager.expectedLengths(for: .pan) == [16])
        #expect(manager.expectedLengths(for: .cvv) == [3])
        #expect(manager.expectedLengths(for: .expDate) == [])
        #expect(manager.expectedLengths(for: .holderName) == [])
    }

    // MARK: clearField

    @Test func clearFieldClearsOnlyTargetField() {
        let manager = makeManager()
        type("123", into: cvvField(manager))
        type("JOHN DOE", into: holderField(manager))
        #expect(manager.hasFieldContent(.cvv))
        #expect(manager.hasFieldContent(.holderName))

        manager.clearField(.cvv)
        #expect(!manager.hasFieldContent(.cvv))
        #expect(!manager.isFieldValid(.cvv))
        #expect(manager.hasFieldContent(.holderName)) // untouched
    }

    @Test func clearFieldPanResetsDigitCount() {
        let manager = makeManager()
        type("4111111111111111", into: panField(manager))
        #expect(manager.panDigitCount == 16)

        manager.clearField(.pan)
        #expect(manager.panDigitCount == 0)
        #expect(!manager.isFieldValid(.pan))
    }

    // MARK: CVV-only (SDK-12287)

    @Test func cvvOnlyExposesItsConfiguredFields() {
        let manager = makeManager(fields: .cvvOnly)
        #expect(manager.configuredFields == [.cvv])
        #expect(manager.isCVVOnly)
        #expect(makeManager().isCVVOnly == false)
    }

    /// Unconfigured fields are hidden and inert, so a host mounting them anyway collects nothing
    /// the form would ever submit. The CVV view stays visible.
    @Test func cvvOnlyHidesTheOtherViews() {
        let manager = makeManager(fields: .cvvOnly)
        #expect(manager.panContainer.isHidden)
        #expect(manager.panContainer.isUserInteractionEnabled == false)
        #expect(manager.expDateView.isHidden)
        #expect(manager.holderNameView.isHidden)
        #expect(manager.cvvView.isHidden == false)
        #expect(manager.cvvView.isUserInteractionEnabled)
    }

    @Test func fullFormLeavesEveryViewVisible() {
        let manager = makeManager()
        #expect(manager.panContainer.isHidden == false)
        #expect(manager.expDateView.isHidden == false)
        #expect(manager.holderNameView.isHidden == false)
    }

    /// State accessors keep answering for unconfigured fields — the E2E state probe reads all four.
    @Test func cvvOnlyStateAccessorsTolerateUnconfiguredFields() {
        let manager = makeManager(fields: .cvvOnly)
        #expect(manager.panDigitCount == 0)
        #expect(manager.isFieldValid(.pan) == false)
        #expect(manager.hasFieldContent(.pan) == false)
        #expect(manager.isFieldFocused(.pan) == false)
        #expect(manager.expectedLengths(for: .pan) == [16])
    }

    /// No PAN field means no BIN lookup will ever narrow the CVV, so both lengths in use are
    /// accepted — web parity while no brand is known, and the Android 1.4.2 rule.
    @Test func cvvOnlyAcceptsThreeOrFourDigits() {
        let manager = makeManager(fields: .cvvOnly)
        #expect(manager.expectedLengths(for: .cvv) == [3, 4])

        type("12", into: cvvField(manager))
        #expect(manager.isFieldValid(.cvv) == false)
        type("123", into: cvvField(manager))
        #expect(manager.isFieldValid(.cvv))
        type("1234", into: cvvField(manager))
        #expect(manager.isFieldValid(.cvv))
        type("12345", into: cvvField(manager))
        #expect(manager.isFieldValid(.cvv) == false)
    }

    @Test func fullFormKeepsTheThreeDigitDefault() {
        let manager = makeManager()
        #expect(manager.expectedLengths(for: .cvv) == [3])
        type("1234", into: cvvField(manager))
        #expect(manager.isFieldValid(.cvv) == false)
    }

    @Test func cvvOnlyClearKeepsBothLengths() {
        let manager = makeManager(fields: .cvvOnly)
        type("1234", into: cvvField(manager))
        manager.clearFields()
        #expect(manager.expectedLengths(for: .cvv) == [3, 4])
        #expect(manager.hasFieldContent(.cvv) == false)
    }

    /// `secureFieldsFormValidityChanged` only weighs configured fields: the CVV alone flips it.
    @Test func cvvOnlyFormValidityFollowsTheCvvAlone() {
        let manager = makeManager(fields: .cvvOnly)
        let delegate = SpyDelegate()
        manager.delegate = delegate

        type("123", into: cvvField(manager))
        #expect(delegate.validityChanges.last == true)

        type("12", into: cvvField(manager))
        #expect(delegate.validityChanges.last == false)
    }

    @Test func cvvOnlySubmitWithEmptyCvvFailsAsIncomplete() {
        let manager = makeManager(fields: .cvvOnly)
        let delegate = SpyDelegate()
        manager.delegate = delegate

        manager.submit()

        #expect(delegate.failures.count == 1)
        if case .fieldsIncomplete = delegate.failures.first {} else {
            Issue.record("expected .fieldsIncomplete, got \(String(describing: delegate.failures.first))")
        }
    }

    /// A configured holder name still only counts when `requiresHolderName` opts it in.
    @Test func cvvAndHolderNameRespectsRequiresHolderName() {
        let optional = makeManager(fields: .init(holderName: .init(), cvv: .init()))
        let spy = SpyDelegate()
        optional.delegate = spy
        type("123", into: cvvField(optional))
        #expect(spy.validityChanges.last == true, "holder name left empty must not block an optional field")

        let required = makeManager(requiresHolderName: true, fields: .init(holderName: .init(), cvv: .init()))
        let requiredSpy = SpyDelegate()
        required.delegate = requiredSpy
        type("123", into: cvvField(required))
        #expect(requiredSpy.validityChanges.last != true)
        type("Jane Doe", into: holderField(required))
        #expect(requiredSpy.validityChanges.last == true)
    }

    // MARK: Per-field placeholders and accessibility

    @Test func perFieldPlaceholderOverridesLegacyPlaceholders() {
        var config = SecureFieldsConfig(
            tenantId: "tenant",
            placeholders: .init(cvv: "legacy"),
            fields: .init(cvv: .init(placeholder: "ex: 1234", accessibilityLabel: "Security code")),
            monitoringEnabled: false
        )
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [FailingURLProtocol.self]
        config.urlSessionOverride = URLSession(configuration: sessionConfig)
        let manager = SecureFieldsManager(config: config)

        #expect(cvvField(manager).placeholder == "ex: 1234")
        #expect(manager.cvvView.accessibilityLabel == "Security code")
        // The value never leaks through the accessibility API, label or not.
        type("1234", into: cvvField(manager))
        #expect(manager.cvvView.accessibilityValue == nil)
    }

    @Test func legacyPlaceholdersStillApplyWhenFieldsSayNothing() {
        var config = SecureFieldsConfig(
            tenantId: "tenant",
            placeholders: .init(pan: "PAN here", cvv: "CVC"),
            monitoringEnabled: false
        )
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [FailingURLProtocol.self]
        config.urlSessionOverride = URLSession(configuration: sessionConfig)
        let manager = SecureFieldsManager(config: config)

        #expect(panField(manager).placeholder == "PAN here")
        #expect(cvvField(manager).placeholder == "CVC")
        #expect(manager.cvvView.accessibilityLabel == nil)
    }

    // MARK: requiresHolderName

    @Test func holderNameExcludedFromFormValidityByDefault() {
        let manager = makeManager()
        let spy = SpyDelegate()
        manager.delegate = spy

        type("4111111111111111", into: panField(manager))
        type("123", into: cvvField(manager))
        type("1230", into: expField(manager))

        #expect(spy.validityChanges.last == true) // holder empty, form still valid
    }

    @Test func holderNameGatesFormValidityWhenRequired() {
        let manager = makeManager(requiresHolderName: true)
        let spy = SpyDelegate()
        manager.delegate = spy

        type("4111111111111111", into: panField(manager))
        type("123", into: cvvField(manager))
        type("1230", into: expField(manager))
        #expect(spy.validityChanges.last != true) // holder empty → not valid yet

        type("JOHN DOE", into: holderField(manager))
        #expect(spy.validityChanges.last == true)
    }

    @Test func submitFailsWhenRequiredHolderNameMissing() {
        let manager = makeManager(requiresHolderName: true)
        let spy = SpyDelegate()
        manager.delegate = spy

        type("4111111111111111", into: panField(manager))
        type("123", into: cvvField(manager))
        type("1230", into: expField(manager))

        manager.submit()
        #expect(spy.failures.count == 1)
        if case .fieldsIncomplete = spy.failures.first {} else {
            Issue.record("expected .fieldsIncomplete, got \(String(describing: spy.failures.first))")
        }
    }

    // MARK: BIN lookup failure

    @Test func binLookupFailureReachesDelegate() async throws {
        let manager = makeManager()
        let spy = SpyDelegate()
        manager.delegate = spy

        type("41111111", into: panField(manager))
        // 300 ms debounce before the request fires, then the stubbed session fails immediately.
        // Polled rather than slept: these suites run in parallel, and a fixed wait flakes as
        // soon as the machine is loaded.
        let deadline = Date().addingTimeInterval(10)
        while spy.binLookupFailures.isEmpty, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(!spy.binLookupFailures.isEmpty)
        #expect(spy.brandsDetected.isEmpty) // failure must not masquerade as "no brands"
    }
}
