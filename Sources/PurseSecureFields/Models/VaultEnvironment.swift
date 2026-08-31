import Foundation

/// Selects which Purse environment this SDK instance talks to — the SDK resolves both
/// endpoints internally, mirroring the Android SDK's `VaultEnvironment`:
///
/// - The vault tokenization/BIN-lookup gateway (`apiRoot`), always under the "vault." subdomain.
/// - The `cf-widget-logger` remote log monitoring endpoint (`monitoringApiRoot`), a different
///   backend service, never under the "vault." subdomain, but always mirroring `apiRoot`'s
///   sandbox/secure word (confirmed with infra).
///
/// No raw URL configuration is required in the host app.
public enum VaultEnvironment: String {
    /// Internal-only, and refused at runtime in a release-signed host app — see
    /// `VaultEnvironment.resolve(_:isDebugHost:)`.
    ///
    /// Compiling it out with `#if DEBUG` (as this case used to be) removed it from the
    /// distributed XCFramework, which is archived in Release: our own E2E suite could not point
    /// the SDK at TEST, where the rest of the platform's test data lives. The SDK ships as one
    /// binary for every merchant regardless of their build type, so the guard has to be a
    /// runtime one, exactly as on Android.
    case test
    case sandbox
    case production

    var apiRoot: String {
        switch self {
        case .test: return "https://api.vault.purse-test.com"
        case .sandbox: return "https://api.vault.purse-sandbox.com"
        case .production: return "https://api.vault.purse-secure.com"
        }
    }

    var monitoringApiRoot: String {
        switch self {
        case .test: return "https://api.purse-test.com"
        case .sandbox: return "https://api.purse-sandbox.com"
        case .production: return "https://api.purse-secure.com"
        }
    }

    /// The environment actually used: `.test` is downgraded to `.production` unless the host app
    /// is itself a development build. A merchant shipping to the App Store must never end up
    /// talking to TEST, whatever they passed.
    static func resolve(_ requested: VaultEnvironment, isDebugHost: Bool) -> VaultEnvironment {
        guard requested == .test, !isDebugHost else { return requested }
        NSLog("PurseSecureFields: VaultEnvironment.test is not allowed in a release-signed app — falling back to production")
        return .production
    }

    /// True when the running app is a development build: the simulator, or a binary whose
    /// provisioning profile carries `get-task-allow` (Xcode-run, development and ad-hoc builds).
    /// App Store and enterprise distribution builds carry neither, which is the iOS equivalent of
    /// Android's `FLAG_DEBUGGABLE`.
    static var isDebugHost: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              // The profile is CMS-signed; the embedded plist is plain text inside it.
              let text = String(data: data, encoding: .isoLatin1) else {
            return false
        }
        return text.contains("<key>get-task-allow</key>") &&
            text.range(of: "<key>get-task-allow</key>\\s*<true/>", options: .regularExpression) != nil
        #endif
    }
}
