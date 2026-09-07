import Foundation
import Testing
@testable import PurseSecureFields

/// Error-relay tests (SDK-12108, gap 19): a non-2xx response whose body doesn't match the
/// documented `{"error": ...}` shape must surface the raw body, not collapse into
/// "Unknown error" — that opacity is what made the Oney 400 undiagnosable from the outside.
struct VaultAPIClientTests {

    private func makeClient(tenantId: String) -> VaultAPIClient {
        VaultAPIClient(baseURL: "https://stub.example.com", session: StubGatewayURLProtocol.makeSession())
    }

    private func makePayload() -> TokenizationPayload {
        TokenizationPayload(
            cvv: "123",
            card: .init(
                pan: "4111111111111111", expiryMonth: 12, expiryYear: 2030,
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
}
