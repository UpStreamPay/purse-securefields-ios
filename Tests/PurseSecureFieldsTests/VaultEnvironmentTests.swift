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

    /// `.test` now ships in the Release binary too — it is guarded at runtime, not by `#if DEBUG`.
    @Test func testResolvesToTheTestHosts() {
        #expect(VaultEnvironment.test.apiRoot == "https://api.vault.purse-test.com")
        #expect(VaultEnvironment.test.monitoringApiRoot == "https://api.purse-test.com")
    }

    // MARK: - Runtime guard

    @Test func testEnvironmentIsAllowedOnADebugHost() {
        #expect(VaultEnvironment.resolve(.test, isDebugHost: true) == .test)
    }

    @Test func testEnvironmentFallsBackToProductionOnAReleaseHost() {
        #expect(VaultEnvironment.resolve(.test, isDebugHost: false) == .production)
    }

    @Test func otherEnvironmentsPassThroughOnAnyHost() {
        #expect(VaultEnvironment.resolve(.sandbox, isDebugHost: false) == .sandbox)
        #expect(VaultEnvironment.resolve(.sandbox, isDebugHost: true) == .sandbox)
        #expect(VaultEnvironment.resolve(.production, isDebugHost: false) == .production)
        #expect(VaultEnvironment.resolve(.production, isDebugHost: true) == .production)
    }

    @Test func simulatorCountsAsADebugHost() {
        // The suite always runs on the simulator, where the SDK must accept .test.
        #expect(VaultEnvironment.isDebugHost)
    }
}
