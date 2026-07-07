/// Selects which `cf-widget-logger` environment remote monitoring logs are tagged with and sent
/// to. Independent of `SecureFieldsConfig.baseURL`, which the host app already controls directly.
public enum MonitoringEnvironment: String {
    #if DEBUG
    /// Internal-only. The distributed XCFramework is always built in Release configuration
    /// (`xcodebuild archive` defaults to Release — see release.yml), so `#if DEBUG` code is
    /// compiled out entirely: this case does not exist in the binary any merchant integrates,
    /// in either their own Debug or Release build. It's only reachable when building this
    /// package from source in a Debug configuration (e.g. local development).
    case test
    #endif
    case sandbox
    case production

    // cf-widget-logger monitoring endpoint — never under the "vault." subdomain that
    // SecureFieldsConfig.baseURL uses (a different backend service — the vault
    // tokenization/BIN-lookup gateway). Always mirrors baseURL's sandbox/secure word
    // (confirmed with infra).
    var apiRoot: String {
        switch self {
        #if DEBUG
        case .test: return "https://api.purse-test.com"
        #endif
        case .sandbox: return "https://api.purse-sandbox.com"
        case .production: return "https://api.purse-secure.com"
        }
    }
}
