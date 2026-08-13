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

    private func makeManager(requiresHolderName: Bool = false) -> SecureFieldsManager {
        var config = SecureFieldsConfig(
            tenantId: "tenant",
            requiresHolderName: requiresHolderName,
            monitoringEnabled: false
        )
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [FailingURLProtocol.self]
        config.testURLSession = URLSession(configuration: sessionConfig)
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
        try await Task.sleep(nanoseconds: 1_200_000_000)

        #expect(!spy.binLookupFailures.isEmpty)
        #expect(spy.brandsDetected.isEmpty) // failure must not masquerade as "no brands"
    }
}
