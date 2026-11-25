import Foundation
import PurseSecureFields
import UIKit

/// The Demo's merchant backend: Alfred (`usp-widget/packages/alfred`).
///
/// Everything a merchant app asks its own backend in the **advanced flow** goes through here —
/// the app SDK configuration at startup, then the payment — because those Purse endpoints take
/// an OAuth2 token no app may hold. Proof-of-concept plumbing: no retries, no pinning, and a
/// backend that authenticates nobody. Do not copy it into an integration.
///
/// `MERCHANT_BACKEND_URL` names it; on the simulator it defaults to Alfred's local port, since
/// the simulator shares the Mac's loopback — `npm run dev` in Alfred is all the setup there is.
/// `ENTITY_ID` scopes the calls. Both are read from the process environment first (a scheme's
/// Run environment, `SIMCTL_CHILD_…`), then from `Info.plist` (`.env` via `scripts/load-env.sh`).
enum DemoBackend {

    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    /// `nil` under the UI tests, which stub the gateway and must never reach a real backend.
    static var baseURL: URL? {
        guard !ProcessInfo.processInfo.arguments.contains("--uitesting") else { return nil }
        #if targetEnvironment(simulator)
        let fallback: String? = "http://localhost:9001"
        #else
        let fallback: String? = nil
        #endif
        return (setting("MERCHANT_BACKEND_URL") ?? fallback).flatMap(URL.init(string:))
    }

    /// The 3DS demo entity on `test` (Paybox / Verifone and CentralPay). Its Purse Vault tenant
    /// is the Demo's default `TENANT_ID`: the two go together — a 3DS transaction versioned for
    /// one tenant is refused on another entity's payment.
    static var entityId: String { setting("ENTITY_ID") ?? "5742b046-f9db-4637-a608-9876b88b16e3" }

    /// A card solution a payment can go to: the partner (the PSP) and its method.
    struct CardSolution {
        let partner: String
        let method: String
    }
    /// The `creditcard` solutions `POST /v2/eligible-solutions` lists for the sample order,
    /// loaded once at launch, and the one picked in the "PSP" control — the first by default.
    @MainActor static var cardSolutions: [CardSolution] = []
    @MainActor static var selectedSolution = 0
    @MainActor static var cardSolution: CardSolution? {
        cardSolutions.indices.contains(selectedSolution) ? cardSolutions[selectedSolution] : nil
    }

    static func setting(_ key: String) -> String? {
        let value = ProcessInfo.processInfo.environment[key]
            ?? Bundle.main.object(forInfoDictionaryKey: key) as? String
        return value?.isEmpty == false ? value : nil
    }

    // MARK: - App SDK configuration

    /// The `data` to pass as `SecureFieldsConfig.appSDKConfiguration`: the backend's answer to
    /// `GET /v2/entities/{entityId}/app-sdk-configuration`, or — when no backend answers — the
    /// same document built locally from `NETCETERA_API_KEY`. `nil` with neither, and Purse 3DS
    /// then reports `.threeDS(.configurationMissing)`.
    ///
    /// A secret: never logged, here or anywhere.
    static func appSDKConfiguration() async -> String? {
        guard baseURL != nil else { return localAppSDKConfiguration }
        do {
            let answer = try await call("GET", "/app_sdk_configuration?entity_id=\(entityId)")
            if let data = answer["data"] as? String { return data }
            throw Failure(errorDescription: "no `data` in the answer")
        } catch {
            NSLog("Demo: no app SDK configuration from the merchant backend (\(error.localizedDescription)) — is Alfred running? NETCETERA_API_KEY fallback: \(localAppSDKConfiguration == nil ? "unset" : "set")")
            return localAppSDKConfiguration
        }
    }

    private static var localAppSDKConfiguration: String? {
        guard let key = setting("NETCETERA_API_KEY") else { return nil }
        let document = ["three_ds": ["vendor": "NETCETERA", "sdk_api_key": key]]
        return (try? JSONSerialization.data(withJSONObject: document))?.base64EncodedString()
    }

    // MARK: - Gateway API key

    /// The merchant's public API key, as Alfred reports it on `/env`. Purse's API gateway asks
    /// for one on `POST /v2/3ds/challenge-result`, so the Demo passes it as
    /// `SecureFieldsConfig.apiKey` when `MONITORING_API_KEY` names none.
    static func gatewayAPIKey() async -> String? {
        guard baseURL != nil else { return nil }
        return (try? await call("GET", "/env"))?["apiKey"] as? String
    }

    // MARK: - Payment

    /// `POST /v2/payments` through the backend, for the card `submit(threeDSEnabled: true)` just
    /// tokenized: the sample order, the first eligible card solution, and the 3DS ids — the `sdk`
    /// block top-level, where a web integration sends `browser`.
    static func createPayment(for result: TokenizationResult) async throws -> [String: Any] {
        guard let transID = result.threeDSServerTransID, let sdk = result.sdk else {
            throw Failure(errorDescription: "submit() returned no 3DS data")
        }
        let (scope, amount) = try await orderScope()

        guard let card = await cardSolution else {
            throw Failure(errorDescription: "no creditcard solution is eligible on entity \(entityId)")
        }

        var payment = scope
        // The block is `Encodable` and already in wire shape: encoding it is the whole hand-off.
        payment["sdk"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(sdk))
        payment["split"] = [[
            "amount": amount,
            "partner": card.partner,
            "method": card.method,
            "vault_form_token": result.vaultFormToken,
            "three_ds_server_trans_id": transID,
        ]]
        return try await call("POST", "/create_payment", body: payment, timeout: 30)
    }

    /// The sample order as the scope `eligible-solutions` and `payments` share: entity, amount,
    /// currency, customer and order.
    private static func orderScope() async throws -> (scope: [String: Any], amount: Int) {
        let sample = try await call("GET", "/order")
        guard let order = (sample["order"] as? [String: Any])?["order"] as? [String: Any],
              let amount = order["amount"] as? Int,
              let currency = order["currency_code"] as? String else {
            throw Failure(errorDescription: "unexpected sample order")
        }
        let buyer = order["customer"] as? [String: Any] ?? [:]
        let billing = buyer["billing_address"] as? [String: Any] ?? [:]
        var customer: [String: Any] = ["reference": buyer["reference"] ?? "ios-demo", "type": "PERSON"]
        customer["email"] = billing["email"]
        customer["locale"] = buyer["locale_code"]
        // A reference of its own: an order is matched on it, and a paid one takes no more payment.
        let v2Order: [String: Any] = [
            "reference": "ios-demo-\(Int(Date().timeIntervalSince1970))",
            "net_amount": amount,
            "tax_amount": order["tax_amount"] ?? 0,
            // As the web demo sends it. No `email` here: the schema refuses it on an address —
            // the cardholder's email goes on `customer`.
            "billing_address": billing.filter {
                ["first_name", "last_name", "address_lines", "city", "postal_code", "country_code"]
                    .contains($0.key)
            },
        ]
        let scope: [String: Any] = [
            "entity_id": entityId, "amount": amount, "currency": currency,
            "customer": customer, "order": v2Order,
        ]
        return (scope, amount)
    }

    /// Asks the backend which solutions are eligible for the sample order and keeps the
    /// `creditcard` ones — the only kind the card form can pay with.
    static func loadCardSolutions() async {
        guard let scope = try? await orderScope().scope,
              let eligible = try? await call("POST", "/eligible_solutions", body: scope) else { return }
        let solutions = (eligible["eligible_solutions"] as? [[String: Any]] ?? []).compactMap { solution -> CardSolution? in
            guard solution["method"] as? String == "creditcard", let partner = solution["partner"] as? String else {
                return nil
            }
            return CardSolution(partner: partner, method: "creditcard")
        }
        await MainActor.run {
            cardSolutions = solutions
            selectedSolution = 0
        }
    }

    /// `GET /v2/payments/{id}` — the truth, as a merchant backend would read it.
    static func payment(_ id: String) async throws -> [String: Any] {
        try await call("GET", "/payment/\(id)?entity_id=\(entityId)")
    }

    /// Ephemeral: the app SDK configuration carries the 3DS SDK's key and must never land in a
    /// URL cache on disk.
    private static let session = URLSession(configuration: .ephemeral)

    /// `timeout` is short for the calls the launch waits on, so an unreachable backend falls back
    /// quickly; a payment gets the long one.
    private static func call(
        _ method: String,
        _ path: String,
        body: [String: Any]? = nil,
        timeout: TimeInterval = 5
    ) async throws -> [String: Any] {
        // Concatenated, not `relativeTo:`, which would drop any path in MERCHANT_BACKEND_URL.
        guard let baseURL, let url = URL(string: baseURL.absoluteString.trimmingTrailingSlash + path) else {
            throw Failure(errorDescription: "no merchant backend configured (MERCHANT_BACKEND_URL)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            // Never for `/app_sdk_configuration`'s success body — only an error body gets here.
            let text = String(data: data.prefix(600), encoding: .utf8) ?? ""
            throw Failure(errorDescription: "\(method) \(url.path) → HTTP \(status) \(text)")
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

// MARK: - The advanced flow, end to end

extension DemoViewController {

    /// What a merchant app does once `submit(threeDSEnabled: true)` has answered: hand the three
    /// values to its backend, then branch on the payment's `authentication` node.
    func pay(with result: TokenizationResult, summary: String) {
        Task { @MainActor in
            do {
                show("\(summary)\n\n→ creating the payment…", color: .secondaryLabel)
                let payment = try await DemoBackend.createPayment(for: result)
                let paymentID = payment["id"] as? String
                let authentication = payment["authentication"] as? [String: Any]
                let status = Self.status(of: payment)

                if let blob = authentication?["challenge_data"] as? String, !blob.isEmpty {
                    // Verdict C. Verbatim: the blob is opaque to everyone but the 3DS SDK.
                    challengeField.text = blob
                    show("\(status)\n\n→ the issuer asks for a challenge…", color: .secondaryLabel)
                    runChallenge(blob, paymentID: paymentID)
                } else {
                    // Frictionless or refused: Secure Fields never hears of the verdict, so the
                    // transaction it opened is the app's to release.
                    manager.releaseThreeDS()
                    let refused = (authentication?["status"] as? String) == "FAILURE"
                    show("\(status)\n\nno challenge — 3DS resources released", color: refused ? .systemRed : .systemGreen)
                }
            } catch {
                manager.releaseThreeDS()
                show("\(summary)\n\nPayment error: \(error.localizedDescription)", color: .systemRed)
            }
        }
    }

    /// Runs the native challenge, then reads the payment back from the backend: what the device
    /// was told is untrusted, the payment is the truth.
    func runChallenge(_ blob: String, paymentID: String?) {
        manager.challenge(blob, presenting: self) { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .failure(let error):
                self.show("Challenge error: \(error)", color: .systemRed)
            case .success(let result):
                // The server's answer, not the device's — `.pending` is a normal ending.
                let text = """
                challenge-result: \(result.result.rawValue)
                payment: \(result.paymentID ?? "—")
                authentication: \(result.authenticationStatus ?? "—")
                authorization: \(result.authorizationStatus ?? "—")
                reason: \(result.reason ?? "—")
                device said: \(result.challengeStatus)
                """
                let color: UIColor = result.result == .rejected ? .systemRed : .systemGreen
                self.show(text, color: color)
                guard let id = result.paymentID ?? paymentID, DemoBackend.baseURL != nil else { return }
                Task { @MainActor in
                    guard let payment = try? await DemoBackend.payment(id) else { return }
                    self.show("\(text)\n\nGET payment (the truth)\n\(Self.status(of: payment))", color: color)
                }
            }
        }
    }

    private func show(_ text: String, color: UIColor) {
        resultLabel.textColor = color
        resultLabel.text = text
    }

    private static func status(of payment: [String: Any]) -> String {
        let authentication = (payment["authentication"] as? [String: Any])?["status"] as? String
        let authorization = (payment["authorization"] as? [String: Any])?["status"] as? String
        return """
        payment: \(payment["id"] as? String ?? "—")
        authentication: \(authentication ?? "—")
        authorization: \(authorization ?? "—")
        """
    }
}

private extension String {
    var trimmingTrailingSlash: String { hasSuffix("/") ? String(dropLast()) : self }
}
