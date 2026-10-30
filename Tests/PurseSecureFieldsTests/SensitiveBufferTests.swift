import Foundation
import Testing
import UIKit
@testable import PurseSecureFields

extension SensitiveBuffer {
    convenience init(_ string: String) {
        self.init()
        append(contentsOf: string.utf8)
    }

    var string: String { withUnsafeBytes { String(decoding: $0, as: UTF8.self) } }
}

/// The SDK's copies of card data must be zeroable in place: wiping a buffer has to reach every
/// byte it ever held, including what a `Data` handed to URLSession reads.
struct SensitiveBufferTests {

    @Test func wipeZeroesWhatItsDataReads() {
        let buffer = SensitiveBuffer("4111111111111111")
        let data = buffer.data()
        #expect(String(decoding: data, as: UTF8.self) == "4111111111111111")

        buffer.wipe()

        #expect(buffer.isEmpty)
        #expect(data.count == 16)
        #expect(data.allSatisfy { $0 == 0 }, "the Data must read the buffer in place, not a copy")
    }

    /// `Data` copies short payloads into its inline storage instead of referencing them. A buffer
    /// of `minimumSharedCount` bytes must be past that threshold, or the copy escapes `wipe()`.
    @Test func wipeAlsoReachesARequestBodySetFromItsData() {
        let buffer = SensitiveBuffer(String(repeating: "7", count: SensitiveBuffer.minimumSharedCount))
        var request = URLRequest(url: URL(string: "https://stub.example.com")!)
        request.httpBody = buffer.data()

        buffer.wipe()

        #expect(request.httpBody?.allSatisfy { $0 == 0 } == true)
    }

    @Test func growingKeepsEveryByte() {
        let buffer = SensitiveBuffer(capacity: 2)
        buffer.append(contentsOf: "5032026098999722327".utf8)
        #expect(buffer.string == "5032026098999722327")
    }

    @Test func wipeZeroesTheWholeAllocation() {
        let buffer = SensitiveBuffer("123")
        #expect(!buffer.isZeroed)

        buffer.wipe()
        buffer.wipe()

        #expect(buffer.isEmpty)
        #expect(buffer.isZeroed)
    }

    // MARK: JSON writer

    @Test func writerEscapesWhatJSONRequires() throws {
        let name = SensitiveBuffer("Zoë \"Jo\" O\\Brien\n\u{1}")
        var json = SensitiveJSONWriter()
        json.beginObject()
        json.key("name")
        json.value(name)
        json.key("n")
        json.value(42)
        json.key("b")
        json.value(false)
        json.key("nested")
        json.beginObject()
        json.key("s")
        json.value("VISA")
        json.endObject()
        json.endObject()

        let object = try #require(
            JSONSerialization.jsonObject(with: Data(json.buffer.string.utf8)) as? [String: Any]
        )
        #expect(object["name"] as? String == "Zoë \"Jo\" O\\Brien\n\u{1}")
        #expect(object["n"] as? Int == 42)
        #expect(object["b"] as? Bool == false)
        #expect((object["nested"] as? [String: Any])?["s"] as? String == "VISA")
    }
}

/// Each field copies its value for tokenization exactly as its `String` accessor reads it.
@MainActor
struct SensitiveFieldCopyTests {

    @Test func panCopyKeepsDigitsOnly() {
        let field = SecurePANField()
        field.text = "4111 1111 1111 1111"
        #expect(field.copyRawValue().string == "4111111111111111")
    }

    @Test func cvvCopyIsTheStoredValue() {
        let field = SecureCVVField()
        field.text = "1234"
        #expect(field.copyRawValue().string == "1234")
    }

    @Test func holderNameCopyIsTrimmedLikeTrimmingCharacters() {
        let field = SecureHolderNameField()
        field.text = " \t Zoë Martin  "
        #expect(field.copyTrimmedValue().string == "Zoë Martin")
    }

    @Test func blankHolderNameCopiesToAnEmptyBuffer() {
        let field = SecureHolderNameField()
        field.text = "   "
        #expect(field.copyTrimmedValue().isEmpty)
    }

    @Test func copyingLeavesTheFieldIntact() {
        let field = SecurePANField()
        field.text = "4111111111111111"
        field.textDidChange()

        field.copyRawValue().wipe()

        #expect(field.rawValue == "4111111111111111")
        #expect(field.isValid)
    }
}
