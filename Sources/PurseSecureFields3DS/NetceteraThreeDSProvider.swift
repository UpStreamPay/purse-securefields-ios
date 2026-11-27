import Foundation
import PurseSecureFields
import ThreeDS_SDK
import UIKit

/// `ThreeDSProvider` on top of the Netcetera 3DS Mobile SDK — the whole of the optional
/// `PurseSecureFields3DS` product.
///
/// Secure Fields finds it by its Objective-C name (`PurseThreeDS.discover()`): linking the
/// product is the whole switch, nothing registers it. The SDK's API key is not here, nor in any
/// artifact — it arrives through `initialize(apiKey:)`, from
/// `SecureFieldsConfig.appSDKConfiguration`.
///
/// Everything on `ThreeDS2Service` is `async`, and the order of the calls is load-bearing —
/// `cleanup()` then `initialize()`, `close()` then `createTransaction`. So every call goes onto
/// one serial chain rather than a `Task` of its own.
@objc(PurseSecureFields3DSProvider)
final class NetceteraThreeDSProvider: NSObject, ThreeDSProvider {

    private let service: ThreeDS2Service = ThreeDS2ServiceSDK()

    private let lock = NSLock()
    private var tail: Task<Void, Never>?
    /// What the live service was initialized with, `nil` when it is not. Not the key itself: a
    /// hash is enough to notice a change, and keeps the secret out of one more place.
    private var initializedWith: (keyHash: Int, production: Bool)?
    private var cachedWarnings: [String] = []

    // MARK: - ThreeDSProvider

    func initialize(apiKey: String, production: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        enqueue { [self] in
            // `ThreeDS2Service` throws `SDKAlreadyInitialized` on a second call, and Secure
            // Fields re-asks on every chain by design, so the no-op is ours to provide — but only
            // for the same configuration. The service is process-wide: a sandbox manager followed
            // by a production one must not leave the non-production roots trusted, nor an old key
            // in use, so a different configuration tears the service down and starts again.
            let wanted = (keyHash: apiKey.hashValue, production: production)
            switch locked({ initializedWith }) {
            case let current? where current == wanted:
                completion(.success(()))
                return
            case .some:
                // Only forgotten once the service really is torn down: believing it is when it
                // is not would make the next `initialize` throw `SDKAlreadyInitialized` forever.
                if (try? await service.cleanup()) != nil {
                    locked {
                        initializedWith = nil
                        cachedWarnings = []
                    }
                }
            case nil:
                break
            }
            do {
                let builder = ConfigurationBuilder()
                try builder.api(key: apiKey)
                if !production {
                    for scheme in NonProductionDirectoryServers.schemes() {
                        try builder.add(scheme)
                    }
                }
                try await service.initialize(
                    builder.configParameters(),
                    locale: nil,
                    uiCustomization: nil
                )
                // Fetched here because `warnings` is synchronous: there is no point at which the
                // caller could await it.
                let warnings = (try? await service.getWarnings()) ?? []
                locked {
                    initializedWith = wanted
                    cachedWarnings = warnings.map {
                        "\($0.getID()) [\($0.getSeverity().rawValue)]: \($0.getMessage())"
                    }
                }
                let version = (try? service.getSDKVersion()) ?? "unknown"
                NSLog("Netcetera3DS: initialized — SDK \(version), \(warnings.count) warning(s)")
                completion(.success(()))
            } catch {
                // The SDK's text, minus the key should it ever repeat it.
                NSLog("Netcetera3DS: initialize failed — \(String(describing: error).replacingOccurrences(of: apiKey, with: "<redacted>"))")
                completion(.failure(error))
            }
        }
    }

    var warnings: [String] { locked { cachedWarnings } }

    func createTransaction(
        directoryServerID: String,
        messageVersion: String,
        completion: @escaping (Result<ThreeDSTransaction, Error>) -> Void
    ) {
        enqueue { [self] in
            do {
                let transaction = try await service.createTransaction(
                    directoryServerId: directoryServerID,
                    messageVersion: messageVersion
                )
                completion(.success(NetceteraThreeDSTransaction(transaction, provider: self)))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func cleanup() {
        enqueue { [self] in
            // Same rule as above: forget the configuration only once the service is torn down.
            guard (try? await service.cleanup()) != nil else { return }
            locked {
                initializedWith = nil
                cachedWarnings = []
            }
        }
    }


    // MARK: - Serial chain

    /// Appends `work` to the single chain every SDK call runs on, so the ordering the
    /// coordinator relies on survives the jump from its synchronous API to the SDK's `async`
    /// one. `Transaction.close()` uses it too, which is why the transaction wrapper holds the
    /// provider.
    func enqueue(_ work: @escaping () async -> Void) {
        lock.lock()
        let previous = tail
        tail = Task {
            await previous?.value
            await work()
        }
        lock.unlock()
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

/// One EMVCo transaction. Holds its `ChallengeStatusReceiver`, which the SDK does not retain.
private final class NetceteraThreeDSTransaction: ThreeDSTransaction {

    private let transaction: Transaction
    private let provider: NetceteraThreeDSProvider
    private var receiver: ChallengeReceiver?

    init(_ transaction: Transaction, provider: NetceteraThreeDSProvider) {
        self.transaction = transaction
        self.provider = provider
    }

    func authenticationRequestParameters() throws -> ThreeDSAuthenticationRequestParameters {
        let parameters = try transaction.getAuthenticationRequestParameters()
        return ThreeDSAuthenticationRequestParameters(
            sdkAppID: parameters.getSDKAppID(),
            sdkTransactionID: parameters.getSDKTransactionId(),
            sdkReferenceNumber: parameters.getSDKReferenceNumber(),
            deviceData: parameters.getDeviceData(),
            sdkEphemeralPublicKey: parameters.getSDKEphemeralPublicKey(),
            messageVersion: parameters.getMessageVersion()
        )
    }

    func doChallenge(
        presenting viewController: UIViewController,
        parameters: ThreeDSChallengeParameters,
        timeoutMinutes: Int,
        completion: @escaping (ThreeDSChallengeStatus) -> Void
    ) {
        // Two ways to fail — `doChallenge` throws, or the receiver reports — and the contract is
        // exactly one completion, so both go through the same once-guard.
        let receiver = ChallengeReceiver(completion: completion)
        self.receiver = receiver

        let challengeParameters = ChallengeParameters(
            threeDSServerTransactionID: parameters.threeDSServerTransactionID,
            acsTransactionID: parameters.acsTransactionID,
            acsRefNumber: parameters.acsRefNumber,
            acsSignedContent: parameters.acsSignedContent
        )

        Task { @MainActor in
            do {
                try await transaction.doChallenge(
                    challengeParameters: challengeParameters,
                    challengeStatusReceiver: receiver,
                    timeOut: timeoutMinutes,
                    inViewController: viewController
                )
            } catch {
                receiver.finish(.runtimeError(String(describing: error)))
            }
        }
    }

    func close() {
        // On the provider's chain: a `close()` that landed after the next `createTransaction`
        // would invalidate the transaction that replaced it.
        provider.enqueue { [transaction] in
            try? await transaction.close()
        }
    }
}

/// Collapses the SDK's five terminal callbacks onto one `ThreeDSChallengeStatus`, once.
private final class ChallengeReceiver: ChallengeStatusReceiver {

    private let lock = NSLock()
    private var completion: ((ThreeDSChallengeStatus) -> Void)?

    init(completion: @escaping (ThreeDSChallengeStatus) -> Void) {
        self.completion = completion
    }

    func finish(_ status: ThreeDSChallengeStatus) {
        lock.lock()
        let completion = self.completion
        self.completion = nil
        lock.unlock()
        completion?(status)
    }

    func completed(completionEvent: CompletionEvent) {
        // Device-side only. The payment outcome comes from `/v2/3ds/challenge-result`.
        finish(.completed(transStatus: completionEvent.getTransactionStatus()))
    }

    func cancelled() {
        finish(.cancelled)
    }

    func timedout() {
        finish(.timedOut)
    }

    func protocolError(protocolErrorEvent: ProtocolErrorEvent) {
        let message = protocolErrorEvent.getErrorMessage()
        finish(.protocolError("\(message.getErrorCode()): \(message.getErrorDescription())"))
    }

    func runtimeError(runtimeErrorEvent: RuntimeErrorEvent) {
        let code = runtimeErrorEvent.getErrorCode() ?? "-"
        finish(.runtimeError("\(code): \(runtimeErrorEvent.getErrorMessage())"))
    }
}

/// The roots of Netcetera's **non-production** Directory Servers and ACS — what a Purse `test` or
/// `sandbox` challenge is signed under. The SDK ships the schemes' production roots only, so
/// without these `doChallenge` ends on "Validation of certificate chain with DS Root certificate
/// failed" before drawing anything.
///
/// Public certificates, published by Netcetera in `NetceteraDemoMerchant.zip` next to the SDK.
/// **Never trusted in production**: `initialize(apiKey:production:)` adds them only when
/// `production` is false. Base64 DER, no PEM armour — the form `Scheme.rootCertificateValues`
/// takes.
enum NonProductionDirectoryServers {

    static let roots: [String] = [
        // CN=3dssprevCA, O=Netcetera AG — preview, valid to 2034 (acq-root-certeq-prev-environment-new.crt)
        (
            "MIIDvDCCAqSgAwIBAgIIXx1HTqXNi9cwDQYJKoZIhvcNAQEMBQAwdDELMAkGA1UEBhMCQ0gxCzAJBgNVBAgTAlpIMQ8wDQYD" +
            "VQQHEwZadXJpY2gxFTATBgNVBAoTDE5ldGNldGVyYSBBRzEbMBkGA1UECxMSQWNxdWlyaW5nIFByb2R1Y3RzMRMwEQYDVQQD" +
            "EwozZHNzcHJldkNBMB4XDTI0MDgwNzEyMDQwMFoXDTM0MDgwNzEyMDQwMFowdDELMAkGA1UEBhMCQ0gxCzAJBgNVBAgTAlpI" +
            "MQ8wDQYDVQQHEwZadXJpY2gxFTATBgNVBAoTDE5ldGNldGVyYSBBRzEbMBkGA1UECxMSQWNxdWlyaW5nIFByb2R1Y3RzMRMw" +
            "EQYDVQQDEwozZHNzcHJldkNBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA355300neGKEJJlcZBH7N0K7t+UX/" +
            "6cgYRGxjlvjOaG7EhuyBYr/7huLbtkUsf0EYxubg5i0ZR7fTDkU5s6JgRhfeENVgusTMPyYNk7iOKsEXwahv4UmuthvOtYid" +
            "V/Ww9y+dvcEb14plX685q9nzNpjxxwg0PAvBIC3a9e6b/6Yx/CE0fnbGNpSQDLYxC8A/vB1y8E+AhRiGAxNNBty/kuUvBlD5" +
            "Kd+fsFjJtU+hI0DEWEXVeeGqU0OZyfLobqPUMnNKYTSGj7HnXUkBbFKXOK7Ey1DgsxBuAliIlWLxatACn9BzsusvqNuSvy/i" +
            "qdwNQZv0CArt4MflWtMIndwRGQIDAQABo1IwUDAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTJ2OZIjKq/SI37IsUjXsbR" +
            "8pFP7jALBgNVHQ8EBAMCAQYwEQYJYIZIAYb4QgEBBAQDAgAHMA0GCSqGSIb3DQEBDAUAA4IBAQAfed9OtVtxPGpzM/JKx8MK" +
            "+ZnWb24sEF2SWhDa78fgk2Easnk+OXkO7uGKSvnnLPuQqDo0bfhaKYpCT/N3SbO/mvt4wNG0psA2He/apoXE3tCuxWXhh8Ju" +
            "dNyDC0BhtSUq6X9bYYM8XsRq4/45z67nyBbZ0Tq1EWLCPJr/6oQqMyMM1oTZwZqDNZc37wNABzUiVum4gTAoXe7p42UuSlur" +
            "YKxfO6ixLhhSNYkmkiaDyvBSpTQIZ+AsdDqB98WHx0baIjJjBeMme+u/PifeFF3CQLRko0IlJQget73fPY4asYxpzLt3YP4M" +
            "enh6u5KTqnq2VPgvhfLLjuGybnCC/+DE"
        ),
        // CN=3dssprevCA, O=netcetera — preview, valid to 2029 (acq-root-certeq-prev-environment.crt)
        (
            "MIIDgTCCAmmgAwIBAgIBATANBgkqhkiG9w0BAQUFADBKMQswCQYDVQQGEwJDSDESMBAGA1UEChMJbmV0Y2V0ZXJhMRIwEAYD" +
            "VQQLEwluZXRjZXRlcmExEzARBgNVBAMTCjNkc3NwcmV2Q0EwHhcNMTkwNjIxMTMyNTAwWhcNMjkwNjIxMTMyNTAwWjBKMQsw" +
            "CQYDVQQGEwJDSDESMBAGA1UEChMJbmV0Y2V0ZXJhMRIwEAYDVQQLEwluZXRjZXRlcmExEzARBgNVBAMTCjNkc3NwcmV2Q0Ew" +
            "ggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCnG2j6qThDxTAx/pAo5SBrVuMhP6zxrn1DYQEMRe4Q/749kuLVFT5t" +
            "RdMiHCwv/DLEtj+OmibVJSzZdMiQQ8PmdsvvSjwh/Z33kBdw+LhgQeBFeix5vD+mXpUtNuPHx8y5kgvcv4vTzOiowgjnLtpJ" +
            "TZaiMbQNUfyLByliA+M00gkAw7GkpMjZpskcF2kCmJHDS1KzmopYp0O2BWrbqFx8aJ7LDCFl47oQsDmmnKbtLaczW5a7y8JF" +
            "oJQjx+wXz+JzxbFG7mVa9EFX9xJSnbAVOoVi7qlQMMBs3T3uo3XATloqJgGz1ZMS2cLYoxUwvkm2XqcLzxeYWwSMVCxq+tWx" +
            "AgMBAAGjcjBwMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFLtgZWfJhfdvCPdqOiGmqCXgJb2zMAsGA1UdDwQEAwIBBjAR" +
            "BglghkgBhvhCAQEEBAMCAAcwHgYJYIZIAYb4QgENBBEWD3hjYSBjZXJ0aWZpY2F0ZTANBgkqhkiG9w0BAQUFAAOCAQEAU2I8" +
            "M6U9c7szAV2gbtcijbMWYmGHSikZxTl6tIFWKbEXR/cNUnWus/4f4vmEZrJt/iYsWfa65Qp7V+5aDgdhhWOqoLNjEmT7MYQF" +
            "QarDpurb4PmCos6xxNt0XfDbsVWJcYjwm/F3kpp/luvI7mPnK0ySSsBZFnWnUAx8bF8hzCAJpuoDBxi8Ny7ND64O9UAT60AS" +
            "5gTpBU4/PgBG5D7W31FMLg1VIc9ltdgctHpJyO/aPkugyNssi8jg093kAOw46/N5dOfcmjjW1UnaRsn/Akhz1YN/DpGQeGNs" +
            "wl506tAbcyJq7Ifzo8e5yj0v00oLHQ8yD5VlLOWxbkDB1kZSZw=="
        ),
        // CN=ca-scheme1, O=NCA — test, valid to 2038 (acq-root-certeq-test-environment.crt)
        (
            "MIIDGDCCAgACCQCy4yEGOiFa6jANBgkqhkiG9w0BAQsFADBOMRMwEQYDVQQDDApjYS1zY2hlbWUxMQwwCgYDVQQKDANOQ0Ex" +
            "DzANBgNVBAcMBlp1cmljaDELMAkGA1UECAwCWkgxCzAJBgNVBAYTAkNIMB4XDTE4MDMzMDA3MDE0M1oXDTM4MDMyNTA3MDE0" +
            "M1owTjETMBEGA1UEAwwKY2Etc2NoZW1lMTEMMAoGA1UECgwDTkNBMQ8wDQYDVQQHDAZadXJpY2gxCzAJBgNVBAgMAlpIMQsw" +
            "CQYDVQQGEwJDSDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAJtZWpM0AwxW0mCfRe5zoii8dQqL+aJYwtC1Bl21" +
            "gIN33PCng3hLEDVShbkxX+pFAna4hvVsapPYo2KSChtPsHF90SGwkmris0/ARezKlZ04BDjlv4/Qr9qDsTeG2fLlSA4zr8ES" +
            "58t/UbYL54qzQ76JCHvT2+rg7ewMAAZrdjz7b4wzZ0caJTPkOAKNF1nob+/vE4gDqxq2wf1DsSgaSAp4PXVfYUEacV5OJ7uE" +
            "IbdTtNe+YO5q+aZDpY+XzH0zDpoMYHpSeOzey7W0vh7X/Ycy4MXyr+XFnwgt8OvfTNjs40jGknxbj3vDFmWnlk0StzUQTxnz" +
            "yh/bC/qrDDET5YMCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAmcQZVu+C4YzgJ9MR5f0UNeSgrOYew5Uxxzb9ksX08WdPjCLq" +
            "VCL/W241HkzbUiH7qdDV5MK1YhLNGcRwo2P+AnSxs4gTo1quE8CW0jL3yBJHElHzPkfFQmoiBuRHu8zzVW8r4oSGut1cuf+m" +
            "A5/dCoUatZacjmgsY1VmmM6XWPlKLFT17h2w4toPOhq5TQfx0Td/7Y3t56jWjH08DT6dq+ei3vgiHIKV4/BZL73t1f9nvn68" +
            "nGIpOc41jSc1LHMLDIvwvvf1tf8XAoCHBMoWJ8j6n0/+LWRt04m8YoHmmy0EUwlh8XNmsFQBsZ/Jz29JawJHIeMbs+7YCP2B" +
            "lf5MDg=="
        ),
    ]

    /// Every pre-configured scheme, with the non-production roots in place of its own. Only the
    /// roots are set: the encryption keys stay the ones the SDK fetches for the API key.
    static func schemes() -> [Scheme] {
        [Scheme.visa(), .mastercard(), .amex(), .diners(), .jcb(), .union(), .cb()].map { scheme in
            scheme.rootCertificateValues = roots
            return scheme
        }
    }
}
