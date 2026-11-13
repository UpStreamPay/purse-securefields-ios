import Foundation
import Testing
@testable import PurseSecureFields

/// `SecureFieldsConfig.urlSessionOverride` bypasses certificate pinning, so it must only take
/// effect on a development host. A release-signed app always gets the pinned client (SDK-12425).
@MainActor
struct SessionOverrideGuardTests {

    /// Two well-formed Base64 SHA-256 values (primary + backup) — enough to switch pinning on.
    private let hashes = [
        Data(repeating: 0xA1, count: 32).base64EncodedString(),
        Data(repeating: 0xB2, count: 32).base64EncodedString(),
    ]

    private func makeConfig(override: URLSession?) -> SecureFieldsConfig {
        var config = SecureFieldsConfig(
            tenantId: "tenant",
            environment: .sandbox,
            pinnedPublicKeyHashes: hashes,
            monitoringEnabled: false
        )
        config.urlSessionOverride = override
        return config
    }

    // MARK: - VaultAPIClient.make

    @Test func overrideIsHonouredOnADebugHost() {
        let client = VaultAPIClient.make(
            baseURL: VaultEnvironment.sandbox.apiRoot,
            pinnedPublicKeyHashes: hashes,
            sessionOverride: StubGatewayURLProtocol.makeSession(),
            isDebugHost: true
        )
        #expect(client.usesSessionOverride)
        #expect(!client.isPinned)
    }

    @Test func overrideIsIgnoredOnAReleaseHost() {
        let client = VaultAPIClient.make(
            baseURL: VaultEnvironment.sandbox.apiRoot,
            pinnedPublicKeyHashes: hashes,
            sessionOverride: StubGatewayURLProtocol.makeSession(),
            isDebugHost: false
        )
        #expect(!client.usesSessionOverride)
        #expect(client.isPinned)
    }

    @Test func noOverrideBuildsThePinnedClientOnAnyHost() {
        for isDebugHost in [true, false] {
            let client = VaultAPIClient.make(
                baseURL: VaultEnvironment.sandbox.apiRoot,
                pinnedPublicKeyHashes: hashes,
                sessionOverride: nil,
                isDebugHost: isDebugHost
            )
            #expect(!client.usesSessionOverride)
            #expect(client.isPinned)
        }
    }

    // MARK: - SecureFieldsManager

    @Test func releaseHostManagerAlwaysUsesThePinnedClient() {
        let manager = SecureFieldsManager(
            config: makeConfig(override: StubGatewayURLProtocol.makeSession()),
            isDebugHost: false
        )
        #expect(!manager.apiClient.usesSessionOverride)
        #expect(manager.apiClient.isPinned)
    }

    @Test func debugHostManagerUsesTheOverride() {
        let manager = SecureFieldsManager(
            config: makeConfig(override: StubGatewayURLProtocol.makeSession()),
            isDebugHost: true
        )
        #expect(manager.apiClient.usesSessionOverride)
    }

    /// The public init reads the real host: the test suite runs on the simulator, a debug host,
    /// so the override the other suites rely on keeps working.
    @Test func publicInitHonoursTheOverrideOnTheSimulator() {
        let manager = SecureFieldsManager(config: makeConfig(override: StubGatewayURLProtocol.makeSession()))
        #expect(manager.apiClient.usesSessionOverride)
    }
}
