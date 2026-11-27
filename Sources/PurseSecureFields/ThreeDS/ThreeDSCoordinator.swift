import Foundation
import UIKit

/// Everything Purse 3DS: the 3DS SDK's lifecycle, versioning, the EMVCo transaction and the
/// native challenge.
///
/// `SecureFieldsManager` owns one and knows nothing else about 3DS — the same division as
/// `MonitoringCoordinator`. No card value ever reaches this class: it works from a form token, a
/// wallet token id and transaction ids.
///
/// All state is touched on the main queue, and every completion is delivered there.
final class ThreeDSCoordinator {

    /// What `submit()` adds to its result once the chain has run.
    struct Preparation {
        let threeDSServerTransID: String
        let sdk: ThreeDSSDKBlock
        let networkTokenUsed: Bool?
    }

    /// EMVCo's minimum, and the `sdkMaxTimeout` Purse announces to the ACS. Keep the two equal:
    /// a shorter one here would end a challenge the ACS still considers open.
    static let challengeTimeoutMinutes = 5

    /// Chains, challenges and stored transactions, per provider, across **every** coordinator of
    /// the process.
    /// The 3DS service behind a provider is process-wide, so `release()` cleans it up only when
    /// none is: a second manager's chain or challenge must not lose the service under it. Keyed
    /// by provider (a merchant app has one) so independent providers — tests — stay independent.
    /// Main queue only.
    private static var busyByProvider: [ObjectIdentifier: Int] = [:]

    private var busy: Int {
        get { provider.map { Self.busyByProvider[ObjectIdentifier($0), default: 0] } ?? 0 }
        set {
            guard let provider else { return }
            Self.busyByProvider[ObjectIdentifier(provider)] = newValue == 0 ? nil : newValue
        }
    }

    /// How long `initialize` and `createTransaction` may take before the chain gives up. Without
    /// a bound, a stalled 3DS SDK (its init fetches configuration over the network) would hold
    /// `submit()`'s latch closed forever and never answer the delegate.
    private let sdkTimeout: TimeInterval

    private let client: ThreeDSAPIClient
    private let tenantId: String
    private let provider: ThreeDSProvider?
    /// The 3DS SDK's API key. Memory only — never logged, never persisted.
    private let apiKey: String?
    private let isProduction: Bool

    private var initWaiters: [(Result<Void, SecureFieldsError>) -> Void] = []
    /// The `initialize` call in flight, `nil` when none is. Identifies it, so a timeout and a
    /// late answer cannot both resolve the waiters.
    private var initAttempt: UUID?
    /// A stored transaction counts as busy: it is waiting for the payment's answer, and another
    /// manager's `release()` must not clean the service up under it.
    private var transaction: ThreeDSTransaction? {
        didSet { busy += (transaction == nil ? 0 : 1) - (oldValue == nil ? 0 : 1) }
    }
    private var currentTransID: String?
    /// Set when the manager goes away (`detach()`). A chain still running then closes the
    /// transaction it gets instead of storing it: nothing could ever challenge or close it.
    private var isDetached = false
    /// The `initialize` timeout. Timers are cancelled as soon as the real answer lands, so they
    /// do not hold this coordinator for 30 s or 6 min more.
    private var initTimer: DispatchWorkItem?
    /// True from `doChallenge` to its terminal callback. While it is, the transaction is the
    /// challenge's: nothing else closes it or cleans the 3DS SDK up under the SDK's own screens.
    private var isChallenging = false

    init(
        tenantId: String,
        client: ThreeDSAPIClient,
        provider: ThreeDSProvider?,
        apiKey: String?,
        isProduction: Bool,
        sdkTimeout: TimeInterval = 30
    ) {
        self.tenantId = tenantId
        self.client = client
        self.provider = provider
        self.apiKey = apiKey
        self.isProduction = isProduction
        self.sdkTimeout = sdkTimeout
    }

    /// Why Purse 3DS cannot run at all, or `nil` when it can: the provider is linked and the
    /// host passed an app SDK configuration carrying the 3DS SDK's API key.
    var unavailability: ThreeDSError? {
        if provider == nil { return .providerUnavailable }
        if apiKey == nil { return .configurationMissing }
        return nil
    }

    /// Why a new chain cannot start right now: `unavailability`, or a challenge on screen. What
    /// `submit(threeDSEnabled: true)` checks before tokenizing anything.
    var blocker: ThreeDSError? {
        unavailability ?? (isChallenging ? .challengeInProgress : nil)
    }

    /// Device integrity warnings from the 3DS SDK. Empty when no provider is linked. The SDK
    /// enforces no device policy on them — that decision is the host's.
    var warnings: [String] { provider?.warnings ?? [] }

    /// Kicked off at Secure Fields init: best effort, non-blocking, once per lifecycle. The
    /// delegate never waits on it, and a failure is retried inside the `submit()` chain.
    func start() {
        guard unavailability == nil else { return }
        ensureInitialized { result in
            // `error` is already redacted: no 3DS SDK key can reach this line.
            if case .failure(let error) = result {
                NSLog("PurseSecureFields: 3DS initialization failed, will retry at submit — \(error)")
            }
        }
    }

    // MARK: - Chain

    /// Versioning + `createTransaction` + the authentication parameters, for a freshly tokenized
    /// card. The tokenization has already happened; nothing here can be retried by itself — a
    /// retry is a new `submit()`.
    func prepare(formToken: String, completion: @escaping (Result<Preparation, SecureFieldsError>) -> Void) {
        run(subject: .freshCard(tenantId: tenantId, formToken: formToken), completion: completion)
    }

    /// The saved-card entry point: no fields, no tokenization.
    func prepareSavedCard(
        _ card: ThreeDSSavedCard,
        networkToken: Bool,
        amount: Int?,
        currency: String?,
        completion: @escaping (Result<Preparation, SecureFieldsError>) -> Void
    ) {
        run(
            subject: card.subject,
            networkToken: networkToken,
            amount: amount,
            currency: currency,
            completion: completion
        )
    }

    /// `self` is held strongly for the whole chain, which every step bounds in time: a host
    /// that does not keep the manager (`submitSavedCard` needs no form) still gets its answer.
    private func run(
        subject: ThreeDSVersioningSubject,
        networkToken: Bool = false,
        amount: Int? = nil,
        currency: String? = nil,
        completion: @escaping (Result<Preparation, SecureFieldsError>) -> Void
    ) {
        onMain {
            // A chain finishing under a live challenge would replace the transaction the
            // challenge is using.
            guard !self.isChallenging else {
                completion(.failure(.threeDS(.challengeInProgress)))
                return
            }
            self.busy += 1
            let finish: (Result<Preparation, SecureFieldsError>) -> Void = { result in
                self.busy -= 1
                completion(result)
            }
            self.ensureInitialized { result in
                if case .failure(let error) = result {
                    finish(.failure(error))
                    return
                }
                let body = ThreeDSVersioningRequest(
                    subject: subject,
                    networkToken: networkToken,
                    amount: amount,
                    currency: currency
                )
                self.client.versioning(body) { versioning in
                    self.onMain {
                        switch versioning {
                        case .failure(let error):
                            finish(.failure(error))
                        case .success(let response):
                            self.makeTransaction(response, completion: finish)
                        }
                    }
                }
            }
        }
    }

    /// No network call of its own — `createTransaction` is asynchronous only because the 3DS
    /// SDK's own API is.
    private func makeTransaction(
        _ versioning: ThreeDSVersioningResponse,
        completion: @escaping (Result<Preparation, SecureFieldsError>) -> Void
    ) {
        guard let provider else {
            completion(.failure(.threeDS(.providerUnavailable)))
            return
        }
        // A `Transaction` left open is the usual cause of a failure on the next
        // `createTransaction`, so the previous one goes before a new one is asked for.
        closeTransaction()

        // One answer only: the SDK's, or the timeout's. A transaction that arrives after the
        // timeout is closed on the spot — nothing else ever would, and it would stay open in the
        // process-wide 3DS service.
        var answered = false
        var timer: DispatchWorkItem?
        let settle: (Result<ThreeDSTransaction, Error>) -> Void = { result in
            guard !answered else {
                if case .success(let late) = result { late.close() }
                return
            }
            answered = true
            timer?.cancel()
            self.finishTransaction(result, versioning: versioning, completion: completion)
        }
        timer = after(sdkTimeout) {
            settle(.failure(ThreeDSError.transactionFailed("createTransaction timed out")))
        }
        provider.createTransaction(
            directoryServerID: versioning.threeDSDirectoryServerID,
            messageVersion: versioning.threeDSProtocolVersion
        ) { result in
            DispatchQueue.main.async { settle(result) }
        }
    }

    private func finishTransaction(
        _ result: Result<ThreeDSTransaction, Error>,
        versioning: ThreeDSVersioningResponse,
        completion: @escaping (Result<Preparation, SecureFieldsError>) -> Void
    ) {
        switch result {
        case .failure(let error):
            completion(.failure(transactionError(error)))
        case .success(let transaction):
            // A challenge started while this chain ran: storing would replace the transaction it
            // is using. And a manager that went away can never challenge or close what is stored.
            guard !isChallenging, !isDetached else {
                transaction.close()
                completion(.failure(.threeDS(isChallenging ? .challengeInProgress : .noActiveTransaction)))
                return
            }
            do {
                let sdk = try ThreeDSSDKBlock(parameters: transaction.authenticationRequestParameters())
                // Two chains can overlap (a saved card while a submit is versioning): the last
                // one wins, and the transaction it replaces is closed, not dropped open.
                closeTransaction()
                // Kept alive: `challenge()` needs this very instance.
                self.transaction = transaction
                self.currentTransID = versioning.threeDSServerTransID
                completion(.success(Preparation(
                    threeDSServerTransID: versioning.threeDSServerTransID,
                    sdk: sdk,
                    networkTokenUsed: versioning.networkTokenUsed
                )))
            } catch {
                // Nothing else will ever close it: it was never stored.
                transaction.close()
                completion(.failure(transactionError(error)))
            }
        }
    }

    /// Provider and SDK text, with the 3DS SDK's API key taken out should it ever repeat it —
    /// this string reaches the host's delegate and the device log. Every piece of provider text
    /// goes through here: errors, `ThreeDSError` values a provider threw, challenge statuses.
    private func redacted(_ text: String) -> String {
        guard let apiKey, !apiKey.isEmpty else { return text }
        return text.replacingOccurrences(of: apiKey, with: "<redacted>")
    }

    private func redacted(_ error: Error) -> String { redacted(String(describing: error)) }

    private func redacted(_ error: ThreeDSError) -> ThreeDSError {
        switch error {
        case .initializationFailed(let detail): return .initializationFailed(redacted(detail))
        case .transactionFailed(let detail): return .transactionFailed(redacted(detail))
        default: return error
        }
    }

    private func redacted(_ status: ThreeDSChallengeStatus) -> ThreeDSChallengeStatus {
        switch status {
        case .protocolError(let detail): return .protocolError(redacted(detail))
        case .runtimeError(let detail): return .runtimeError(redacted(detail))
        default: return status
        }
    }

    private func transactionError(_ error: Error) -> SecureFieldsError {
        if let error = error as? ThreeDSError {
            return .threeDS(redacted(error))
        }
        return .threeDS(.transactionFailed(redacted(error)))
    }

    // MARK: - Challenge

    func challenge(
        _ challengeData: String,
        presenting viewController: UIViewController,
        completion: @escaping (Result<ThreeDSChallengeResult, SecureFieldsError>) -> Void
    ) {
        onMain { [weak self] in
            guard let self else { return }
            if let unavailability = self.unavailability {
                completion(.failure(.threeDS(unavailability)))
                return
            }
            guard !self.isChallenging else {
                completion(.failure(.threeDS(.challengeInProgress)))
                return
            }
            guard let transaction = self.transaction, let transID = self.currentTransID else {
                completion(.failure(.threeDS(.noActiveTransaction)))
                return
            }
            let blob: ThreeDSChallengeBlob
            do {
                blob = try ThreeDSChallengeBlob.decode(challengeData)
            } catch let error as ThreeDSError {
                completion(.failure(.threeDS(error)))
                return
            } catch {
                completion(.failure(.threeDS(.invalidChallengeData)))
                return
            }
            // The blob and the live transaction must describe the same authentication; a
            // mismatch means the caller handed back challenge data from another payment.
            guard blob.threeDSServerTransID == transID else {
                completion(.failure(.threeDS(.invalidChallengeData)))
                return
            }

            self.isChallenging = true
            self.busy += 1
            // One ending only: the SDK's terminal callback, or — should it never come — a watchdog
            // a minute past the challenge timeout, so the manager can never be stuck on a
            // challenge that will not end. `self` is held strongly until then: challenge-result
            // must run and the resources be released on every ending, even if the host lets go of
            // the manager while the 3DS SDK's screens are up.
            var ended = false
            var watchdog: DispatchWorkItem?
            let end: (ThreeDSChallengeStatus) -> Void = { status in
                guard !ended else { return }
                ended = true
                watchdog?.cancel()
                self.finishChallenge(status: status, transID: transID, completion: completion)
            }
            watchdog = self.after(TimeInterval(Self.challengeTimeoutMinutes * 60 + 60)) { end(.timedOut) }
            transaction.doChallenge(
                presenting: viewController,
                parameters: blob.challengeParameters,
                timeoutMinutes: Self.challengeTimeoutMinutes
            ) { status in
                self.onMain { end(status) }
            }
        }
    }

    /// Every terminal callback lands here — completed, cancelled, timed out, protocol and
    /// runtime errors alike. None of them is the payment outcome, so the result is always read
    /// back from the server; the resources are then released whatever the answer.
    private func finishChallenge(
        status rawStatus: ThreeDSChallengeStatus,
        transID: String,
        completion: @escaping (Result<ThreeDSChallengeResult, SecureFieldsError>) -> Void
    ) {
        let status = redacted(rawStatus)
        switch status {
        case .protocolError(let detail), .runtimeError(let detail):
            NSLog("PurseSecureFields: 3DS challenge ended on an error — \(detail)")
        default:
            break
        }
        client.challengeResult(threeDSServerTransID: transID) { result in
            self.onMain {
                self.isChallenging = false
                self.busy -= 1
                self.release()
                completion(result.map { $0.asResult(challengeStatus: status) })
            }
        }
    }

    // MARK: - Lifecycle

    /// Closes the transaction and cleans the 3DS SDK up. Called after every terminal challenge
    /// callback and — because Secure Fields never learns of a frictionless verdict, which
    /// happens at the host or its backend — exposed to the host as
    /// `SecureFieldsManager.releaseThreeDS()`. The next chain re-initializes. A no-op while a
    /// challenge is running: the challenge releases everything itself when it ends.
    func release() {
        onMain { [weak self] in
            guard let self, !self.isChallenging else { return }
            self.closeTransaction()
            // Not while another manager's chain or challenge runs on the shared service: it would
            // lose the service under it. The next chain re-asks `initialize` anyway.
            guard let provider = self.provider, self.busy == 0 else { return }
            provider.cleanup()
        }
    }

    /// Closes this coordinator's own transaction and nothing else. What `deinit` calls: a
    /// `cleanup()` there would tear the shared 3DS service down under another manager, and the
    /// hop to the main queue would be too late anyway — the coordinator is already going.
    /// The manager is going away: close what it holds, and make a chain still running close
    /// its transaction rather than store it. What `deinit` calls.
    func detach() {
        isDetached = true
        closeTransaction()
    }

    func closeTransaction() {
        // A running challenge owns its transaction; it is closed when the challenge ends.
        guard !isChallenging else { return }
        transaction?.close()
        transaction = nil
        currentTransID = nil
    }

    private func ensureInitialized(_ completion: @escaping (Result<Void, SecureFieldsError>) -> Void) {
        onMain {
            guard let provider = self.provider else {
                completion(.failure(.threeDS(.providerUnavailable)))
                return
            }
            guard let apiKey = self.apiKey else {
                completion(.failure(.threeDS(.configurationMissing)))
                return
            }
            // Joins the attempt in flight, if any. Otherwise asks again — deliberately with no
            // "already ready" short-circuit: the 3DS service is a process-wide singleton, another
            // `SecureFieldsManager` (the demo's mode switch rebuilds one) can have cleaned it up
            // since, and a cached answer would then send `createTransaction` at a torn-down
            // service. `initialize` is a no-op after a success, so asking again is cheap; a
            // previous failure is retried here, which is the retry `start()` promises.
            self.initWaiters.append(completion)
            guard self.initAttempt == nil else { return }
            let attempt = UUID()
            self.initAttempt = attempt
            self.initTimer = self.after(self.sdkTimeout) { [weak self] in
                self?.settleInitialization(attempt, .failure(ThreeDSError.initializationFailed("initialize timed out")))
            }
            provider.initialize(apiKey: apiKey, production: self.isProduction) { result in
                self.onMain { self.settleInitialization(attempt, result) }
            }
        }
    }

    /// Resolves the waiters of one `initialize` attempt — once: the timeout and a late answer
    /// cannot both. A late success is not lost either: the next chain asks the provider again,
    /// and it answers at once.
    private func settleInitialization(_ attempt: UUID, _ result: Result<Void, Error>) {
        guard initAttempt == attempt else { return }
        initAttempt = nil
        initTimer?.cancel()
        initTimer = nil
        let outcome: Result<Void, SecureFieldsError>
        switch result {
        case .success:
            outcome = .success(())
        case .failure(let error as ThreeDSError):
            outcome = .failure(.threeDS(redacted(error)))
        case .failure(let error):
            outcome = .failure(.threeDS(.initializationFailed(redacted(error))))
        }
        let waiters = initWaiters
        initWaiters = []
        waiters.forEach { $0(outcome) }
    }

    /// A cancellable one-shot on the main queue.
    private func after(_ delay: TimeInterval, _ work: @escaping () -> Void) -> DispatchWorkItem {
        let item = DispatchWorkItem(block: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return item
    }

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}
