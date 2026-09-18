import Testing
@testable import PurseSecureFields

/// The per-field configuration: presence decides rendering, `cvv` is the only
/// mandatory field, and the legacy `SecureFieldsPlaceholders` still applies where a field says
/// nothing of its own.
struct SecureFieldsFieldsConfigTests {

    @Test func allIsTheDefaultAndConfiguresEveryField() {
        let config = SecureFieldsConfig(tenantId: "t", monitoringEnabled: false)
        #expect(config.fields.configuredFields == [.pan, .cvv, .expDate, .holderName])
        #expect(config.fields.isCVVOnly == false)
    }

    @Test func cvvOnlyConfiguresJustTheCvv() {
        let fields = SecureFieldsFieldsConfig.cvvOnly
        #expect(fields.configuredFields == [.cvv])
        #expect(fields.isCVVOnly)
        #expect(fields.pan == nil)
        #expect(fields.expDate == nil)
        #expect(fields.holderName == nil)
    }

    @Test func cvvAlwaysCounts() {
        let fields = SecureFieldsFieldsConfig(expDate: .init(), holderName: .init())
        #expect(fields.configuredFields == [.cvv, .expDate, .holderName])
        #expect(fields.isCVVOnly, "no PAN field means CVV-only, whatever else is mounted")
    }

    /// SDK-12287: this combination used to trap in `init`, killing the host app before any view
    /// was mounted. It must now build like any other — nothing rules on it before the gateway.
    @Test func panWithoutExpDateConstructs() {
        let fields = SecureFieldsFieldsConfig(pan: .init())
        #expect(fields.configuredFields == [.pan, .cvv])
        #expect(fields.isCVVOnly == false, "a PAN field is configured, so this is not the CVV-only form")
        #expect(fields.expDate == nil)
    }

    @Test func perFieldOptionsAreKept() {
        let fields = SecureFieldsFieldsConfig(cvv: .init(placeholder: "ex: 1234", accessibilityLabel: "Security code"))
        #expect(fields.cvv.placeholder == "ex: 1234")
        #expect(fields.cvv.accessibilityLabel == "Security code")
        #expect(fields.config(for: .cvv)?.placeholder == "ex: 1234")
        #expect(fields.config(for: .pan) == nil)
    }
}
