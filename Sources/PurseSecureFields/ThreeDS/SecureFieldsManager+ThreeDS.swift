import UIKit

/// The Purse 3DS surface. `submit(threeDSEnabled:)` lives with the rest of `submit()`; everything
/// that has no card form behind it is here.
public extension SecureFieldsManager {

    /// True when Purse 3DS can run at all: the `PurseSecureFields3DS` product is linked **and**
    /// `SecureFieldsConfig.appSDKConfiguration` carries the 3DS SDK's API key. False means
    /// `submit(threeDSEnabled: true)`, `submitSavedCard(_:)` and `challenge(_:presenting:)` all
    /// fail — with `.threeDS(.providerUnavailable)` or `.threeDS(.configurationMissing)`.
    var isThreeDSAvailable: Bool { threeDS.unavailability == nil }

    /// Device integrity warnings raised by the 3DS SDK (`getWarnings()`), empty until it has
    /// initialized. The SDK enforces no policy on them: refusing, flagging or ignoring a HIGH
    /// severity is the host's decision.
    var threeDSWarnings: [String] { threeDS.warnings }

    /// Authenticates a card saved in oneWallet — no card form, no tokenization.
    ///
    /// Versions the saved card with `device_channel: APP`, builds the EMVCo transaction and
    /// resolves with the `submit()` shape minus `vaultFormToken` and `card`. When the token also
    /// needs a CVV, run the existing CVV-only form next to this call: its `vaultFormToken` goes
    /// on the payment as it does today, this call's ids go beside it.
    ///
    /// `.threeDS(.cardNotEligible)` is the **"not eligible"** answer — unknown or inactive token,
    /// not saved through the Purse Vault, unknown brand, card not in the session, all reported
    /// the same way. Show the card fields instead; do not retry.
    ///
    /// - Parameters:
    ///   - card: the wallet token id and its owner — the client session (session flow) or the
    ///     entity and customer reference (advanced flow).
    ///   - networkToken: ask for network-token mode. The answer's `networkTokenUsed` says whether
    ///     it happened: `false` means versioning fell back to the FPAN and the payment is an
    ///     ordinary saved-card one.
    ///   - amount: minor units, **advanced flow only** — the split amount must equal it.
    ///     The session flow takes the amount from the session; leave it `nil` there.
    ///   - currency: ISO 4217, advanced flow only.
    ///   - completion: called on the main queue.
    func submitSavedCard(
        _ card: ThreeDSSavedCard,
        networkToken: Bool = false,
        amount: Int? = nil,
        currency: String? = nil,
        completion: @escaping (Result<ThreeDSSavedCardResult, SecureFieldsError>) -> Void
    ) {
        threeDS.prepareSavedCard(
            card,
            networkToken: networkToken,
            amount: amount,
            currency: currency
        ) { result in
            completion(result.map {
                ThreeDSSavedCardResult(
                    threeDSServerTransID: $0.threeDSServerTransID,
                    sdk: $0.sdk,
                    networkTokenUsed: $0.networkTokenUsed
                )
            })
        }
    }

    /// Runs the 3DS challenge natively, on the transaction the last `submit()` /
    /// `submitSavedCard(_:)` built.
    ///
    /// Call it when the payment answer says `authentication.status == "IN_PROGRESS"` with an
    /// `authentication.challenge_data` — a Purse 3DS `C` has no `redirection`, so the redirect
    /// surface is never opened for it. Pass the blob **verbatim**; it is opaque.
    ///
    /// The 3DS SDK draws every screen over `viewController`; Secure Fields renders nothing. When
    /// the cardholder is done — however it ended, cancel and error included — the outcome is read
    /// back from the server and the 3DS resources are released.
    ///
    /// The result is the server's, not the device's. `.pending` is a normal ending: hand over to
    /// the merchant backend, which confirms on `GET /v2/payments/{id}` or the webhook. Do not
    /// loop on this call.
    ///
    /// - Parameter completion: called on the main queue.
    func challenge(
        _ challengeData: String,
        presenting viewController: UIViewController,
        completion: @escaping (Result<ThreeDSChallengeResult, SecureFieldsError>) -> Void
    ) {
        threeDS.challenge(challengeData, presenting: viewController, completion: completion)
    }

    /// Closes the EMVCo transaction and cleans the 3DS SDK up.
    ///
    /// `challenge(_:presenting:)` does this itself. Call it on the **frictionless** path — a
    /// `Y` / `A` verdict, or a refusal — which Secure Fields never hears about: the verdict
    /// reaches the host or its backend, not the SDK, and a `Transaction` left open is the usual
    /// cause of a failure on the next one. Call it once the 3DS flow is over, not while a
    /// `submit` / `submitSavedCard(_:)` is still running; during a challenge it does nothing (the
    /// challenge releases everything itself). The next chain re-initializes.
    func releaseThreeDS() {
        threeDS.release()
    }
}
