import Foundation
import Testing
@testable import PurseSecureFields

/// Error-relay tests: a non-2xx response whose body doesn't match the
/// documented `{"error": ...}` shape must surface the raw body, not collapse into
/// "Unknown error" — that opacity is what made the Oney 400 undiagnosable from the outside.
struct VaultAPIClientTests {

    private func makeClient(tenantId: String) -> VaultAPIClient {
        VaultAPIClient(baseURL: "https://stub.example.com", session: StubGatewayURLProtocol.makeSession())
    }

    private func makePayload() -> TokenizationPayload {
        TokenizationPayload(
            cvv: SensitiveBuffer("123"),
            card: .init(
                pan: SensitiveBuffer("4111111111111111"), expiryMonth: 12, expiryYear: 2030,
                cardHolderName: nil, saveToken: false, selectedNetwork: "VISA"
            )
        )
    }

    private func tokenize(tenantId: String) async -> Result<TokenizationResponse, SecureFieldsError> {
        // The client must outlive the round-trip: `perform` captures itself weakly and drops the
        // completion if it has been deallocated, which would hang the continuation forever.
        let client = makeClient(tenantId: tenantId)
        return await withCheckedContinuation { continuation in
            client.tokenize(tenantId: tenantId, payload: makePayload()) {
                continuation.resume(returning: $0)
            }
        }
    }

    @Test func documentedErrorShapeIsDecoded() async throws {
        let tenantId = "t-\(UUID().uuidString)"
        StubGatewayURLProtocol.register(tenantId: tenantId) { _, _ in
            .init(statusCode: 400, body: #"{"error":"pan is invalid"}"#)
        }

        let result = await tokenize(tenantId: tenantId)

        guard case .failure(.apiError(let message, let statusCode)) = result else {
            Issue.record("expected apiError, got \(result)")
            return
        }
        #expect(message == "pan is invalid")
        #expect(statusCode == 400)
    }

    @Test func undocumentedErrorBodyIsRelayedRaw() async throws {
        let tenantId = "t-\(UUID().uuidString)"
        let body = #"{"message":"birth_date is not an accepted field"}"#
        StubGatewayURLProtocol.register(tenantId: tenantId) { _, _ in
            .init(statusCode: 400, body: body)
        }

        let result = await tokenize(tenantId: tenantId)

        guard case .failure(.apiError(let message, _)) = result else {
            Issue.record("expected apiError, got \(result)")
            return
        }
        #expect(message == body)
    }

    @Test func emptyErrorBodyFallsBackToUnknownError() async throws {
        let tenantId = "t-\(UUID().uuidString)"
        StubGatewayURLProtocol.register(tenantId: tenantId) { _, _ in
            .init(statusCode: 400, body: "")
        }

        let result = await tokenize(tenantId: tenantId)

        guard case .failure(.apiError(let message, _)) = result else {
            Issue.record("expected apiError, got \(result)")
            return
        }
        #expect(message == "Unknown error")
    }

    @Test func binLookupErrorRelaysBody() async throws {
        let tenantId = "t-\(UUID().uuidString)"
        StubGatewayURLProtocol.register(tenantId: tenantId) { _, _ in
            .init(statusCode: 403, body: #"{"detail":"tenant not allowed"}"#)
        }

        let client = makeClient(tenantId: tenantId)
        let result: Result<BinLookupResult, SecureFieldsError> = await withCheckedContinuation { continuation in
            client.binLookup(tenantId: tenantId, firstDigits: "41111111") {
                continuation.resume(returning: $0)
            }
        }

        guard case .failure(.apiError(let message, let statusCode)) = result else {
            Issue.record("expected apiError, got \(result)")
            return
        }
        #expect(message == #"{"detail":"tenant not allowed"}"#)
        #expect(statusCode == 403)
    }

    // MARK: Card data wiped

    /// The payload's card values are zeroed as soon as the body has been built from them,
    /// before the request even goes out.
    @Test func payloadIsWipedOnceTheBodyIsBuilt() {
        let tenantId = "t-\(UUID().uuidString)"
        StubGatewayURLProtocol.register(tenantId: tenantId) { _, _ in
            .init(statusCode: 200, body: #"{"form_token":"tok"}"#)
        }
        let payload = makePayload()

        makeClient(tenantId: tenantId).tokenize(tenantId: tenantId, payload: payload) { _ in }

        #expect(payload.cvv!.isZeroed)
        #expect(payload.card!.pan.isZeroed)
    }

    /// The body is zeroed once the gateway has answered, whatever the answer — and is still
    /// intact on the wire until then.
    @Test(arguments: [200, 400, 503])
    func bodyIsWipedOnceAnswered(statusCode: Int) async throws {
        let tenantId = "t-\(UUID().uuidString)"
        StubGatewayURLProtocol.register(tenantId: tenantId) { _, _ in
            .init(statusCode: statusCode, body: #"{"form_token":"tok"}"#)
        }
        let body = TokenizationPayload(cvv: SensitiveBuffer("123"), card: nil).jsonBody()
        let view = body.data()
        let client = makeClient(tenantId: tenantId)

        await withCheckedContinuation { continuation in
            client.tokenize(tenantId: tenantId, body: body) { _ in continuation.resume() }
        }

        let sent = try #require(StubGatewayURLProtocol.requests(tenantId: tenantId).last?.body)
        let json = try #require(try JSONSerialization.jsonObject(with: sent) as? [String: Any])
        #expect(json["cvv"] as? String == "123")
        #expect(body.isZeroed)
        #expect(view.allSatisfy { $0 == 0 })
    }
}
