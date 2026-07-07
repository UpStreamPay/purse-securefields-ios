import Testing
@testable import PurseSecureFields

struct VaultEnvironmentTests {

    @Test func sandboxResolvesToTheSandboxHosts() {
        #expect(VaultEnvironment.sandbox.apiRoot == "https://api.vault.purse-sandbox.com")
        #expect(VaultEnvironment.sandbox.monitoringApiRoot == "https://api.purse-sandbox.com")
    }

    @Test func productionResolvesToTheSecureHosts() {
        #expect(VaultEnvironment.production.apiRoot == "https://api.vault.purse-secure.com")
        #expect(VaultEnvironment.production.monitoringApiRoot == "https://api.purse-secure.com")
    }

    // .test only exists in Debug builds (see VaultEnvironment) — this test itself only compiles
    // in Debug, which is how the test target always builds.
    #if DEBUG
    @Test func testResolvesToTheTestHosts() {
        #expect(VaultEnvironment.test.apiRoot == "https://api.vault.purse-test.com")
        #expect(VaultEnvironment.test.monitoringApiRoot == "https://api.purse-test.com")
    }
    #endif
}
