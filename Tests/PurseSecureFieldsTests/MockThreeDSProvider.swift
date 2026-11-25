import Foundation
import UIKit
@testable import PurseSecureFields

/// Stands in for the Netcetera SDK of the optional `PurseSecureFields3DS` product — the whole
/// point of `ThreeDSProvider` being a protocol. Records what the chain asked of it.
///
/// `PurseThreeDS.register(_:)` is process-wide, so while a test holds this provider registered
/// every `SecureFieldsManager` built by a suite running in parallel calls `initialize` on it,
/// from whatever thread built it. Every property is therefore guarded — an unsynchronised
/// counter here is a data race across the whole test bundle, not just this suite.
final class MockThreeDSProvider: ThreeDSProvider, @unchecked Sendable {

    private let lock = NSLock()

    private func locked<T>(_ work: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }; return work()
    }

    private var _initializeResult: Result<Void, Error> = .success(())
    var initializeResult: Result<Void, Error> {
        get { locked { _initializeResult } }
        set { locked { _initializeResult = newValue } }
    }

    private var _createError: Error?
    var createError: Error? {
        get { locked { _createError } }
        set { locked { _createError = newValue } }
    }

    private var _warnings: [String] = []
    var warnings: [String] {
        get { locked { _warnings } }
        set { locked { _warnings = newValue } }
    }

    private var _initializeCount = 0
    var initializeCount: Int { locked { _initializeCount } }

    private var _cleanupCount = 0
    var cleanupCount: Int { locked { _cleanupCount } }

    private var _createdTransactions: [MockThreeDSTransaction] = []
    var createdTransactions: [MockThreeDSTransaction] { locked { _createdTransactions } }

    private var _lastDirectoryServerID: String?
    var lastDirectoryServerID: String? { locked { _lastDirectoryServerID } }

    private var _lastMessageVersion: String?
    var lastMessageVersion: String? { locked { _lastMessageVersion } }

    private var _parameters = ThreeDSAuthenticationRequestParameters(
        sdkAppID: "app-id",
        sdkTransactionID: "sdk-trans-id",
        sdkReferenceNumber: "3DS_LOA_SDK_NCSA_020100_00123",
        deviceData: "device-data-jwe",
        sdkEphemeralPublicKey: #"{"kty":"EC","crv":"P-256","x":"x-value","y":"y-value"}"#,
        messageVersion: "2.2.0"
    )
    var parameters: ThreeDSAuthenticationRequestParameters {
        get { locked { _parameters } }
        set { locked { _parameters = newValue } }
    }

    /// How the next `doChallenge` ends.
    private var _challengeStatus: ThreeDSChallengeStatus = .completed(transStatus: "Y")
    var challengeStatus: ThreeDSChallengeStatus {
        get { locked { _challengeStatus } }
        set { locked { _challengeStatus = newValue } }
    }

    /// Mirrors `ThreeDS2Service`: a process-wide service that `cleanup()` tears down and that
    /// `createTransaction` refuses to work without. This is what makes the shared-lifecycle
    /// tests mean something.
    private var _isInitialized = false
    var isInitialized: Bool { locked { _isInitialized } }

    struct NotInitialized: Error {}

    private var _lastAPIKey: String?
    var lastAPIKey: String? { locked { _lastAPIKey } }

    private var _lastProduction: Bool?
    var lastProduction: Bool? { locked { _lastProduction } }

    private var _holdInitialize = false
    /// Never answers `initialize` — a stalled 3DS SDK.
    var holdInitialize: Bool {
        get { locked { _holdInitialize } }
        set { locked { _holdInitialize = newValue } }
    }

    private var _holdChallenge = false
    /// `doChallenge` waits for `finishHeldChallenge()` instead of ending at once.
    var holdChallenge: Bool {
        get { locked { _holdChallenge } }
        set { locked { _holdChallenge = newValue } }
    }

    func initialize(apiKey: String, production: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        if holdInitialize { return }
        let result = locked { () -> Result<Void, Error> in
            _initializeCount += 1
            _lastAPIKey = apiKey
            _lastProduction = production
            if case .success = _initializeResult { _isInitialized = true }
            return _initializeResult
        }
        completion(result)
    }

    func createTransaction(
        directoryServerID: String,
        messageVersion: String,
        completion: @escaping (Result<ThreeDSTransaction, Error>) -> Void
    ) {
        let made = locked { () -> Result<ThreeDSTransaction, Error> in
            _lastDirectoryServerID = directoryServerID
            _lastMessageVersion = messageVersion
            guard _isInitialized else { return .failure(NotInitialized()) }
            if let _createError { return .failure(_createError) }
            let transaction = MockThreeDSTransaction(parameters: _parameters, status: _challengeStatus, hold: _holdChallenge)
            _createdTransactions.append(transaction)
            return .success(transaction)
        }
        completion(made)
    }

    func cleanup() {
        locked {
            _cleanupCount += 1
            _isInitialized = false
        }
    }
}

final class MockThreeDSTransaction: ThreeDSTransaction, @unchecked Sendable {

    private let lock = NSLock()
    private let parameters: ThreeDSAuthenticationRequestParameters
    private let status: ThreeDSChallengeStatus

    private func locked<T>(_ work: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }; return work()
    }

    private var _closeCount = 0
    var closeCount: Int { locked { _closeCount } }

    private var _challengeParameters: ThreeDSChallengeParameters?
    var challengeParameters: ThreeDSChallengeParameters? { locked { _challengeParameters } }

    private var _timeoutMinutes: Int?
    var timeoutMinutes: Int? { locked { _timeoutMinutes } }

    private let hold: Bool
    private var _held: ((ThreeDSChallengeStatus) -> Void)?

    init(parameters: ThreeDSAuthenticationRequestParameters, status: ThreeDSChallengeStatus, hold: Bool = false) {
        self.parameters = parameters
        self.status = status
        self.hold = hold
    }

    /// Ends a challenge started with `hold`.
    func finishHeldChallenge() {
        let completion = locked { () -> ((ThreeDSChallengeStatus) -> Void)? in
            defer { _held = nil }
            return _held
        }
        completion?(status)
    }

    func authenticationRequestParameters() throws -> ThreeDSAuthenticationRequestParameters { parameters }

    func doChallenge(
        presenting viewController: UIViewController,
        parameters: ThreeDSChallengeParameters,
        timeoutMinutes: Int,
        completion: @escaping (ThreeDSChallengeStatus) -> Void
    ) {
        locked {
            _challengeParameters = parameters
            _timeoutMinutes = timeoutMinutes
            if hold { _held = completion }
        }
        if !hold { completion(status) }
    }

    func close() { locked { _closeCount += 1 } }
}
