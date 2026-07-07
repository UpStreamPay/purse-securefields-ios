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
    #if DEBUG
    /// Internal-only. The distributed XCFramework is always built in `Release` configuration
    /// (`xcodebuild archive` in release.yml), so `#if DEBUG` code — including this case
    /// entirely — is compiled out of what every merchant integrates, in both their own Debug
    /// and Release builds. Only reachable when building this package from source in a Debug
    /// configuration (local development).
    case test
    #endif
    case sandbox
    case production

    var apiRoot: String {
        switch self {
        #if DEBUG
        case .test: return "https://api.vault.purse-test.com"
        #endif
        case .sandbox: return "https://api.vault.purse-sandbox.com"
        case .production: return "https://api.vault.purse-secure.com"
        }
    }

    var monitoringApiRoot: String {
        switch self {
        #if DEBUG
        case .test: return "https://api.purse-test.com"
        #endif
        case .sandbox: return "https://api.purse-sandbox.com"
        case .production: return "https://api.purse-secure.com"
        }
    }
}
