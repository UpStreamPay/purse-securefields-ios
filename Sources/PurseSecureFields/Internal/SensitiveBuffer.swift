import Foundation

/// Card bytes the SDK can overwrite. A Swift `String` is immutable and its storage is released
/// without being cleared, so a PAN or CVV held in one stays readable in a memory dump until the
/// allocator happens to reuse that memory. This buffer owns its allocation and zeroes it on
/// `wipe()`, on `deinit`, and every time it outgrows it — no copy of its bytes is ever left behind.
/// See docs/security/security.md, "Card data in memory".
///
/// A class, not a struct: a copy-on-write value would leave stray, unzeroed copies of the bytes
/// wherever it was mutated while shared.
final class SensitiveBuffer {

    private var pointer: UnsafeMutablePointer<UInt8>
    private var capacity: Int
    private(set) var count = 0
    /// Set once `data()` has handed the allocation out: growing past it would free memory a
    /// `Data` still reads from.
    private var isShared = false

    init(capacity: Int = 32) {
        self.capacity = max(capacity, 1)
        pointer = .allocate(capacity: self.capacity)
        pointer.initialize(repeating: 0, count: self.capacity)
    }

    deinit {
        wipe()
        pointer.deallocate()
    }

    /// The fewest bytes `data()` can share in place. `Data` copies a payload of up to 14 bytes
    /// (on 64-bit) into its inline storage instead of referencing it — a copy `wipe()` cannot
    /// reach. 16 leaves a margin; `SensitiveBufferTests` pins the behaviour.
    static let minimumSharedCount = 16

    var isEmpty: Bool { count == 0 }

    /// True when every byte of the allocation is zero, as `wipe()` leaves it.
    var isZeroed: Bool {
        UnsafeBufferPointer(start: pointer, count: capacity).allSatisfy { $0 == 0 }
    }

    func append(_ byte: UInt8) {
        if count == capacity { grow() }
        pointer[count] = byte
        count += 1
    }

    func append<S: Sequence>(contentsOf bytes: S) where S.Element == UInt8 {
        for byte in bytes { append(byte) }
    }

    func append(contentsOf other: SensitiveBuffer) {
        other.withUnsafeBytes { append(contentsOf: $0) }
    }

    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try body(UnsafeRawBufferPointer(start: pointer, count: count))
    }

    /// A `Data` reading this buffer's bytes in place, not a copy of them: `wipe()` zeroes what the
    /// `Data` (and a `URLRequest` body set from it) reads too. The `Data` keeps the buffer alive,
    /// so the allocation is only released — zeroed — once nothing reads it any more.
    /// The buffer must hold at least `minimumSharedCount` bytes, and must not be appended to
    /// afterwards.
    func data() -> Data {
        assert(count >= Self.minimumSharedCount, "Data would copy these bytes inline, out of wipe()'s reach")
        isShared = true
        return Data(
            bytesNoCopy: pointer,
            count: count,
            deallocator: .custom { _, _ in withExtendedLifetime(self) {} }
        )
    }

    /// Zeroes the whole allocation in place. Idempotent.
    func wipe() {
        // memset_s, unlike memset, may not be elided as a dead store.
        _ = memset_s(pointer, capacity, 0, capacity)
        count = 0
    }

    private func grow() {
        assert(!isShared, "SensitiveBuffer appended to after data() handed its bytes out")
        let newCapacity = capacity * 2
        let grown = UnsafeMutablePointer<UInt8>.allocate(capacity: newCapacity)
        grown.initialize(repeating: 0, count: newCapacity)
        grown.update(from: pointer, count: count)
        _ = memset_s(pointer, capacity, 0, capacity)
        pointer.deallocate()
        pointer = grown
        capacity = newCapacity
    }
}

/// Minimal JSON object writer for the tokenization request body. `JSONEncoder` needs the card
/// values as `String`s and returns the body as a `Data` the SDK cannot zero; this writes straight
/// into a `SensitiveBuffer`. Supports only what the request needs — nested objects of string, int
/// and bool values — and does not validate nesting.
struct SensitiveJSONWriter {

    let buffer = SensitiveBuffer(capacity: 256)
    private var needsComma = false

    mutating func beginObject() {
        buffer.append(UInt8(ascii: "{"))
        needsComma = false
    }

    mutating func endObject() {
        buffer.append(UInt8(ascii: "}"))
        needsComma = true
    }

    mutating func key(_ name: String) {
        if needsComma { buffer.append(UInt8(ascii: ",")) }
        appendQuoted(name.utf8)
        buffer.append(UInt8(ascii: ":"))
        needsComma = false
    }

    mutating func value(_ value: SensitiveBuffer) {
        value.withUnsafeBytes { appendQuoted($0) }
        needsComma = true
    }

    mutating func value(_ value: String) {
        appendQuoted(value.utf8)
        needsComma = true
    }

    mutating func value(_ value: Int) {
        buffer.append(contentsOf: String(value).utf8)
        needsComma = true
    }

    mutating func value(_ value: Bool) {
        buffer.append(contentsOf: (value ? "true" : "false").utf8)
        needsComma = true
    }

    /// Appends insignificant trailing whitespace (RFC 8259 `ws`) up to `count` bytes, so a short
    /// body can still be shared in place by `SensitiveBuffer.data()`.
    mutating func pad(toCount count: Int) {
        while buffer.count < count { buffer.append(UInt8(ascii: " ")) }
    }

    /// Escapes what RFC 8259 requires. Working on UTF-8 bytes is safe: every byte of a multi-byte
    /// sequence is ≥ 0x80, so none of them can be mistaken for a quote, a backslash or a control.
    private func appendQuoted<S: Sequence>(_ bytes: S) where S.Element == UInt8 {
        buffer.append(UInt8(ascii: "\""))
        for byte in bytes {
            switch byte {
            case UInt8(ascii: "\""), UInt8(ascii: "\\"):
                buffer.append(UInt8(ascii: "\\"))
                buffer.append(byte)
            case 0x00..<0x20:
                buffer.append(contentsOf: "\\u00".utf8)
                buffer.append(Self.hex[Int(byte >> 4)])
                buffer.append(Self.hex[Int(byte & 0x0F)])
            default:
                buffer.append(byte)
            }
        }
        buffer.append(UInt8(ascii: "\""))
    }

    private static let hex = Array("0123456789abcdef".utf8)
}
