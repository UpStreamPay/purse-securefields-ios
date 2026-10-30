import Testing
import UIKit
@testable import PurseSecureFields

/// Regression tests for the PCI field-isolation controls.
/// These guard against host-app bypass of the text/attributedText/accessibilityValue nil overrides,
/// the masked UITextInput reads (`text(in:)`, `attributedText(in:)`), and pasteboard-leakage via
/// copy/cut on the PAN field.
@MainActor
struct SecureFieldIsolationTests {

    // MARK: - SecureBaseField text isolation (F1)

    @Test func panField_textAlwaysNil() {
        let field = SecurePANField()
        field.text = "4111111111111111"
        field.textDidChange()
        #expect(field.text == nil)
    }

    @Test func panField_attributedTextAlwaysNil() {
        let field = SecurePANField()
        field.text = "4111111111111111"
        field.textDidChange()
        #expect(field.attributedText == nil)
    }

    @Test func panField_accessibilityValueAlwaysNil() {
        let field = SecurePANField()
        field.text = "4111111111111111"
        field.textDidChange()
        #expect(field.accessibilityValue == nil)
    }

    @Test func panField_kvcTextAlwaysNil() {
        let field = SecurePANField()
        field.text = "4111111111111111"
        field.textDidChange()
        // KVC calls the Swift property getter, which returns nil
        #expect(field.value(forKey: "text") == nil)
    }

    @Test func cvvField_textAlwaysNil() {
        let field = SecureCVVField()
        field.text = "123"
        field.textDidChange()
        #expect(field.text == nil)
    }

    @Test func cvvField_attributedTextAlwaysNil() {
        let field = SecureCVVField()
        field.text = "123"
        field.textDidChange()
        #expect(field.attributedText == nil)
    }

    @Test func cvvField_accessibilityValueAlwaysNil() {
        let field = SecureCVVField()
        field.text = "123"
        field.textDidChange()
        #expect(field.accessibilityValue == nil)
    }

    @Test func expDateField_attributedTextAlwaysNil() {
        let field = SecureExpDateField()
        field.text = "12/30"
        field.textDidChange()
        #expect(field.attributedText == nil)
    }

    @Test func holderNameField_attributedTextAlwaysNil() {
        let field = SecureHolderNameField()
        field.text = "John Doe"
        field.textDidChange()
        #expect(field.attributedText == nil)
    }

    // MARK: - UITextField cast bypass (the original attack vector)

    @Test func panField_castToUITextField_textStillNil() {
        let field = SecurePANField()
        field.text = "4111111111111111"
        field.textDidChange()
        let casted = field as UITextField
        #expect(casted.text == nil)
        #expect(casted.attributedText == nil)
        #expect(casted.accessibilityValue == nil)
    }

    @Test func cvvField_castToUITextField_textStillNil() {
        let field = SecureCVVField()
        field.text = "123"
        field.textDidChange()
        let casted = field as UITextField
        #expect(casted.text == nil)
        #expect(casted.attributedText == nil)
        #expect(casted.accessibilityValue == nil)
    }

    // MARK: - UITextInput reads (SDK-12548)

    private func fullRange(of input: UITextInput) -> UITextRange {
        input.textRange(from: input.beginningOfDocument, to: input.endOfDocument)!
    }

    @Test func panField_textInRangeIsMasked() {
        let field = SecurePANField()
        field.text = "4111111111111111"
        field.textDidChange()
        let input = field as UITextInput
        #expect(input.text(in: fullRange(of: input)) == "•••• •••• •••• ••••")
    }

    @Test func panField_attributedTextInRangeIsMasked() {
        let field = SecurePANField()
        field.text = "4111111111111111"
        field.textDidChange()
        let range = fullRange(of: field)
        #expect(field.attributedText(in: range).string == "•••• •••• •••• ••••")
    }

    @Test func panField_partialTextInRangeIsMasked() {
        let field = SecurePANField()
        field.text = "4111111111111111"
        field.textDidChange()
        let start = field.position(from: field.beginningOfDocument, offset: 5)!
        let end = field.position(from: start, offset: 4)!
        #expect(field.text(in: field.textRange(from: start, to: end)!) == "••••")
    }

    @Test func cvvField_textInRangeIsMasked() {
        let field = SecureCVVField()
        field.text = "123"
        field.textDidChange()
        #expect(field.text(in: fullRange(of: field)) == "•••")
        #expect(field.attributedText(in: fullRange(of: field)).string == "•••")
    }

    @Test func expDateField_textInRangeIsMasked() {
        let field = SecureExpDateField()
        field.text = "1230"
        field.textDidChange()
        #expect(field.text(in: fullRange(of: field)) == "•••••")
        #expect(field.attributedText(in: fullRange(of: field)).string == "•••••")
    }

    @Test func holderNameField_textInRangeIsMasked() {
        let field = SecureHolderNameField()
        field.text = "John Doe"
        field.textDidChange()
        #expect(field.text(in: fullRange(of: field)) == "•••• •••")
        #expect(field.attributedText(in: fullRange(of: field)).string == "•••• •••")
    }

    @Test func emptyField_textInRangeIsEmpty() {
        let field = SecurePANField()
        #expect(field.text(in: fullRange(of: field)) == "")
    }

    /// UITextInput offsets are UTF-16 units, so the mask must keep the UTF-16 length exactly —
    /// the keyboard bridge range-maths against it.
    @Test func mask_keepsUTF16LengthAndWhitespaceOnly() {
        let name = "Zoe\u{301} \u{1F600}\tO'Neil"
        let masked = SecureBaseField.masked(name)
        #expect(masked.utf16.count == name.utf16.count)
        #expect(masked.unicodeScalars.allSatisfy { $0 == "•" || $0.properties.isWhitespace })
        #expect(masked.split(whereSeparator: \.isWhitespace).count == 3)
    }

    /// Per-character rects are public UITextInput API. With proportional figures a `1` measured
    /// ~3pt narrower than other digits, so geometry alone located digits of the PAN. Rects snap
    /// to the pixel grid, so they are compared position by position across two different PANs
    /// rather than against each other.
    @Test(arguments: [nil, UIFont.systemFont(ofSize: 22, weight: .bold)])
    func panField_characterRectsDoNotDependOnTheDigits(styleFont: UIFont?) throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.makeKeyAndVisible()

        func characterRects(for digits: String) throws -> [CGRect] {
            let field = SecurePANField(frame: CGRect(x: 0, y: 0, width: 360, height: 44))
            window.addSubview(field)
            defer { field.removeFromSuperview() }
            if let styleFont { field.applyStyle(SecureFieldsStyle(font: styleFont)) }
            field.becomeFirstResponder()
            field.text = digits
            field.textDidChange()
            field.layoutIfNeeded()
            return try (0..<19).map { offset in
                let start = try #require(field.position(from: field.beginningOfDocument, offset: offset))
                let end = try #require(field.position(from: start, offset: 1))
                return field.firstRect(for: try #require(field.textRange(from: start, to: end)))
            }
        }

        let narrow = try characterRects(for: "1111111111111111")
        let wide = try characterRects(for: "8888888888888888")
        #expect(narrow.allSatisfy { $0.width > 0 })
        #expect(narrow == wide)
    }

    // MARK: - Host-app perspective (SDK-12548 acceptance)

    /// Mirrors what a host app can do with the public API alone: take the views the manager
    /// exposes, cast them to `UITextField`, and try every read accessor UIKit offers.
    @Test func hostApp_castToUITextField_readsNoCardData() throws {
        var config = SecureFieldsConfig(tenantId: "isolation-\(UUID().uuidString)", monitoringEnabled: false)
        config.urlSessionOverride = StubGatewayURLProtocol.makeSession()
        let manager = SecureFieldsManager(config: config)

        let entries: [(view: UIView, typed: String, secret: String)] = [
            (manager.panContainer, "4111111111111111", "4111"),
            (manager.cvvView, "123", "123"),
            (manager.expDateView, "1230", "12"),
            (manager.holderNameView, "John Doe", "John"),
        ]

        for entry in entries {
            let field = try #require(
                (entry.view as? UITextField) ?? entry.view.subviews.compactMap { $0 as? UITextField }.first
            )
            // Typing goes through the internal path; the reads below use only what UITextField exposes.
            let secure = try #require(field as? SecureBaseField)
            secure.text = entry.typed
            secure.textDidChange()

            let range = fullRange(of: field)
            let reads: [String?] = [
                field.text,
                field.attributedText?.string,
                field.accessibilityValue,
                field.value(forKey: "text") as? String,
                field.text(in: range),
                field.attributedText(in: range).string,
            ]
            for read in reads {
                #expect(read?.contains(entry.secret) != true, "\(type(of: field)) leaked \(read ?? "")")
                #expect(read?.contains(where: \.isNumber) != true, "\(type(of: field)) leaked a digit")
            }
        }
    }

    // MARK: - storedText / rawValue still accessible internally

    @Test func panField_rawValueStillReadable() {
        let field = SecurePANField()
        field.text = "4111111111111111"
        field.textDidChange()
        // Internal API works; public API returns nil
        #expect(field.rawValue == "4111111111111111")
    }

    // MARK: - PAN copy/cut blocked (F4)

    @Test func panField_copyBlocked() {
        let field = SecurePANField()
        #expect(field.canPerformAction(#selector(UIResponder.copy(_:)), withSender: nil) == false)
    }

    @Test func panField_cutBlocked() {
        let field = SecurePANField()
        #expect(field.canPerformAction(#selector(UIResponder.cut(_:)), withSender: nil) == false)
    }

    @Test func panField_dragDelegateInstalled() {
        // The field sets itself as UITextDragDelegate and returns [] from itemsForDrag,
        // which suppresses all drag operations. Verify the delegate is wired.
        let field = SecurePANField()
        #expect(field.textDragDelegate === field)
    }
}
