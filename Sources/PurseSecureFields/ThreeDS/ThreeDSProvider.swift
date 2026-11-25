import Foundation
import UIKit

/// The EMVCo authentication request parameters a 3DS SDK produces locally, with no network call.
///
/// Field names are the EMVCo ones (`AuthenticationRequestParameters` on the Netcetera SDK). The
/// wire mapping — snake_case, `sdk` prefix dropped, ephemeral key as a JWK object — is
/// `ThreeDSSDKBlock`'s job, not the provider's: a provider never forwards a getter name.
public struct ThreeDSAuthenticationRequestParameters {
    public let sdkAppID: String
    public let sdkTransactionID: String
    public let sdkReferenceNumber: String
    /// `getDeviceData()` — the JWE of the device data collected at init.
    public let deviceData: String
    /// `getSDKEphemeralPublicKey()` — a JSON **string** holding a JWK, exactly as the SDK returns
    /// it. Parsed into an object by `ThreeDSSDKBlock`; a string on the wire is a 400.
    public let sdkEphemeralPublicKey: String
    /// `getMessageVersion()`. Not sent: the server already holds the version it versioned with.
    public let messageVersion: String

    public init(
        sdkAppID: String,
        sdkTransactionID: String,
        sdkReferenceNumber: String,
        deviceData: String,
        sdkEphemeralPublicKey: String,
        messageVersion: String
    ) {
        self.sdkAppID = sdkAppID
        self.sdkTransactionID = sdkTransactionID
        self.sdkReferenceNumber = sdkReferenceNumber
        self.deviceData = deviceData
        self.sdkEphemeralPublicKey = sdkEphemeralPublicKey
        self.messageVersion = messageVersion
    }
}

/// The four ACS values a `01` challenge blob carries, handed to the 3DS SDK's
/// `ChallengeParameters`.
public struct ThreeDSChallengeParameters {
    public let threeDSServerTransactionID: String
    public let acsTransactionID: String
    public let acsRefNumber: String
    public let acsSignedContent: String

    public init(
        threeDSServerTransactionID: String,
        acsTransactionID: String,
        acsRefNumber: String,
        acsSignedContent: String
    ) {
        self.threeDSServerTransactionID = threeDSServerTransactionID
        self.acsTransactionID = acsTransactionID
        self.acsRefNumber = acsRefNumber
        self.acsSignedContent = acsSignedContent
    }
}

/// How a native challenge ended, device-side.
///
/// **None of these is the payment outcome.** Every case means "the challenge is over"; what the
/// payment became is read back from the server by `POST /v2/3ds/challenge-result` — see
/// `ThreeDSChallengeResult`. `transStatus` on `.completed` is device-side information only.
public enum ThreeDSChallengeStatus: Equatable {
    case completed(transStatus: String?)
    case cancelled
    case timedOut
    case protocolError(String)
    case runtimeError(String)
}

/// One EMVCo transaction, alive from `createTransaction` to `close()`.
///
/// The same instance must serve the authentication parameters and the challenge: the coordinator
/// keeps it until a terminal outcome or `releaseThreeDS()`.
public protocol ThreeDSTransaction: AnyObject {
    func authenticationRequestParameters() throws -> ThreeDSAuthenticationRequestParameters

    /// Runs the native challenge. The SDK draws every screen; nothing is rendered by Secure
    /// Fields or by the caller. `timeoutMinutes` is 5 — the value Purse announces to the ACS as
    /// `sdkMaxTimeout`; a shorter one would end a challenge the ACS still considers open.
    func doChallenge(
        presenting viewController: UIViewController,
        parameters: ThreeDSChallengeParameters,
        timeoutMinutes: Int,
        completion: @escaping (ThreeDSChallengeStatus) -> Void
    )

    func close()
}

/// The 3DS SDK behind Secure Fields.
///
/// The Netcetera 3DS Mobile SDK sits behind this protocol, in the optional
/// `PurseSecureFields3DS` product — so the core builds, tests and runs with no Netcetera
/// dependency at all, and `submit(threeDSEnabled: true)` fails fast with
/// `.threeDS(.providerUnavailable)` when that product is not linked. The SDK's API key is in no
/// artifact: it arrives at runtime through `SecureFieldsConfig.appSDKConfiguration`.
public protocol ThreeDSProvider: AnyObject {
    /// `ThreeDS2Service.initialize(...)` — collects the device data locally, no ACS round trip.
    /// Called once per lifecycle at Secure Fields init, best effort, and retried inside the
    /// `submit()` chain if it failed. Must be safe to call again after a success (a no-op
    /// with the same `apiKey` and `production`, a clean re-initialization with different ones) and
    /// after `cleanup()`.
    ///
    /// `apiKey` is the 3DS SDK's own key, read from `SecureFieldsConfig.appSDKConfiguration`.
    /// It is a secret: hand it to the SDK and nothing else — never log it, never persist it.
    ///
    /// `production` is false on `test` and `sandbox`, whose Directory Servers and ACS sign
    /// under non-production roots the provider must then trust — and must never trust otherwise.
    func initialize(apiKey: String, production: Bool, completion: @escaping (Result<Void, Error>) -> Void)

    /// `getWarnings()` — device integrity warnings, surfaced through
    /// `SecureFieldsManager.threeDSWarnings`. No device policy is enforced by the SDK.
    var warnings: [String] { get }

    /// `ThreeDS2Service.createTransaction(...)` — asynchronous on the Netcetera SDK, so this is
    /// completion-based too. Bridging it synchronously would mean blocking the main queue on a
    /// semaphore, which deadlocks the moment the SDK hops to main itself.
    func createTransaction(
        directoryServerID: String,
        messageVersion: String,
        completion: @escaping (Result<ThreeDSTransaction, Error>) -> Void
    )

    /// `ThreeDS2Service.cleanup()`. The next `initialize` must work after it.
    func cleanup()
}

/// Where Secure Fields finds the 3DS provider.
///
/// By default the `PurseSecureFields3DS` product is discovered at runtime: it exposes a class named
/// `PurseSecureFields3DSProvider` (declared `@objc(PurseSecureFields3DSProvider)`, with a
/// no-argument `init`) conforming to `ThreeDSProvider`. Linking the product is the whole switch
/// for the provider — matching Android, where the module's presence on the classpath is. The
/// 3DS SDK's API key is a separate matter: `SecureFieldsConfig.appSDKConfiguration`.
///
/// `register(_:)` overrides that lookup, for tests and for a host that links the provider
/// differently.
public enum PurseThreeDS {
    /// The Objective-C–visible name the 3DS product exports.
    static let providerClassName = "PurseSecureFields3DSProvider"

    private static let lock = NSLock()
    private static var registered: ThreeDSProvider?
    private static var didDiscover = false
    private static var discovered: ThreeDSProvider?

    /// Installs a provider explicitly, replacing runtime discovery. `nil` restores it.
    public static func register(_ provider: ThreeDSProvider?) {
        lock.lock()
        registered = provider
        lock.unlock()
    }

    /// The provider in force, or `nil` when the 3DS product is not linked.
    public static var provider: ThreeDSProvider? {
        lock.lock()
        defer { lock.unlock() }
        if let registered { return registered }
        if !didDiscover {
            didDiscover = true
            discovered = discover()
        }
        return discovered
    }

    /// Forgets a cached discovery. Tests only.
    static func resetDiscovery() {
        lock.lock()
        didDiscover = false
        discovered = nil
        lock.unlock()
    }

    private static func discover() -> ThreeDSProvider? {
        guard let type = NSClassFromString(providerClassName) as? NSObject.Type else { return nil }
        return type.init() as? ThreeDSProvider
    }
}
