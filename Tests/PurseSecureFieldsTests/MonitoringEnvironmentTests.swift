import Testing
@testable import PurseSecureFields

struct MonitoringEnvironmentTests {

    @Test func sandboxResolvesToTheSandboxHost() {
        #expect(MonitoringEnvironment.sandbox.apiRoot == "https://api.purse-sandbox.com")
    }

    @Test func productionResolvesToTheSecureHost() {
        #expect(MonitoringEnvironment.production.apiRoot == "https://api.purse-secure.com")
    }

    // .test only exists in Debug builds (see MonitoringEnvironment) — this test itself only
    // compiles in Debug, which is how the test target always builds.
    #if DEBUG
    @Test func testResolvesToTheTestHost() {
        #expect(MonitoringEnvironment.test.apiRoot == "https://api.purse-test.com")
    }
    #endif
}
