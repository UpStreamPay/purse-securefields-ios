import XCTest

final class DemoUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    // MARK: - Launch helpers

    private func launch(tokenizeSuccess: Bool? = nil, cvvOnly: Bool = false) {
        app.launchArguments.append("--uitesting")
        if cvvOnly {
            app.launchArguments.append("--cvv-only")
            // A CVV-only tokenization echoes no `card` block.
            app.launchEnvironment["MOCK_TOKENIZE_RESPONSE"] = #"{"form_token":"tok_cvv_only"}"#
        }
        if let success = tokenizeSuccess {
            if success {
                app.launchEnvironment["MOCK_TOKENIZE_RESPONSE"] = """
                {"form_token":"tok_test_abc123","card":{"bin":"411111","last_four_digits":"1111"}}
                """
            } else {
                app.launchEnvironment["MOCK_TOKENIZE_ERROR_CODE"] = "422"
                app.launchEnvironment["MOCK_TOKENIZE_ERROR_BODY"] = #"{"error":"Card declined"}"#
            }
        }
        app.launch()
        // The first query after launch can run before the form is laid out: wait for the field
        // every mode mounts, instead of letting the first assertion race it.
        XCTAssertTrue(app.secureTextFields["cvv_field"].waitForExistence(timeout: 10), "the form never appeared")
    }

    /// Taps `field` and types `text`, once the tap has given it keyboard focus. A tap that lands
    /// while the screen is still settling leaves no first responder, and `typeText` then fails
    /// with "Neither element nor any descendant has keyboard focus".
    private func enter(_ text: String, into field: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(field.waitForExistence(timeout: 5), "\(field) does not exist", file: file, line: line)
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        for _ in 0..<3 {
            field.tap()
            if XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: focused, object: field)], timeout: 2) == .completed {
                field.typeText(text)
                return
            }
        }
        XCTFail("\(field) never got keyboard focus", file: file, line: line)
    }

    private func dismissKeyboard() {
        // Tap the nav bar title area to reliably resign first responder
        app.navigationBars.firstMatch.tap()
    }

    private func fillValidCard() {
        enter("4111111111111111", into: app.textFields["pan_field"])
        enter("1230", into: app.textFields["expiry_field"])
        enter("John Doe", into: app.textFields["holder_field"])
        enter("123", into: app.secureTextFields["cvv_field"])

        dismissKeyboard()
    }

    // MARK: - Tests

    func testInitialState() {
        launch()
        XCTAssertFalse(app.buttons["pay_button"].isEnabled)
        XCTAssertTrue(app.buttons["clear_button"].isEnabled)
        XCTAssertEqual(app.otherElements["pan_container"].value as? String, "empty")
        XCTAssertEqual(app.otherElements["cvv_container"].value as? String, "empty")
        XCTAssertEqual(app.otherElements["expiry_container"].value as? String, "empty")
        XCTAssertEqual(app.otherElements["holder_container"].value as? String, "empty")
    }

    func testInvalidPANShowsErrorState() {
        launch()
        enter("4111111111111112", into: app.textFields["pan_field"]) // bad Luhn
        // Move focus to another field to trigger PAN editingDidEnd
        app.textFields["expiry_field"].tap()
        dismissKeyboard()
        let panContainer = app.otherElements["pan_container"]
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'invalid'"), object: panContainer)
        wait(for: [exp], timeout: 3)
    }

    func testValidFormEnablesPayButton() {
        launch(tokenizeSuccess: true)
        fillValidCard()
        XCTAssertTrue(app.buttons["pay_button"].isEnabled)
        XCTAssertEqual(app.otherElements["pan_container"].value as? String, "valid")
        XCTAssertEqual(app.otherElements["cvv_container"].value as? String, "valid")
        XCTAssertEqual(app.otherElements["expiry_container"].value as? String, "valid")
        XCTAssertEqual(app.otherElements["holder_container"].value as? String, "valid")
    }

    func testSuccessfulTokenization() {
        launch(tokenizeSuccess: true)
        fillValidCard()
        app.buttons["pay_button"].tap()

        let result = app.staticTexts["result_label"]
        let predicate = NSPredicate(format: "label CONTAINS 'tok_test_abc123'")
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: result)
        wait(for: [exp], timeout: 10)
    }

    func testAPIError() {
        launch(tokenizeSuccess: false)
        fillValidCard()
        app.buttons["pay_button"].tap()

        let result = app.staticTexts["result_label"]
        let predicate = NSPredicate(format: "label CONTAINS '422' AND label CONTAINS 'Card declined'")
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: result)
        wait(for: [exp], timeout: 10)
    }

    // MARK: - CVV-only

    func testCVVOnlyMountsOnlyTheCvvAndTokenizes() {
        launch(cvvOnly: true)

        XCTAssertFalse(app.textFields["pan_field"].exists, "a CVV-only form mounts no PAN field")
        XCTAssertFalse(app.textFields["expiry_field"].exists)
        XCTAssertFalse(app.textFields["holder_field"].exists)
        XCTAssertFalse(app.buttons["pay_button"].isEnabled)

        // 4 digits are accepted while no brand is known (a saved Amex must stay submittable).
        enter("1234", into: app.secureTextFields["cvv_field"])
        dismissKeyboard()

        XCTAssertEqual(app.otherElements["cvv_container"].value as? String, "valid")
        XCTAssertTrue(app.buttons["pay_button"].isEnabled)

        app.buttons["pay_button"].tap()
        let result = app.staticTexts["result_label"]
        let predicate = NSPredicate(format: "label CONTAINS 'tok_cvv_only'")
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: result)
        wait(for: [exp], timeout: 10)
    }

    /// Naming the saved card's brand narrows the CVV-only field: Amex wants 4 digits, and a typed
    /// 3-digit CVV turns invalid instead of being truncated.
    func testCVVOnlyBrandNarrowsTheExpectedLength() {
        launch(cvvOnly: true)
        XCTAssertEqual(app.staticTexts["cvv_label"].label, "CVV (3 or 4 digits)")

        let cvv = app.secureTextFields["cvv_field"]
        enter("123", into: cvv)
        dismissKeyboard()
        XCTAssertEqual(app.otherElements["cvv_container"].value as? String, "valid")

        // The border stays neutral while the field keeps focus, so judge validity through the
        // Pay button and the debug panel instead.
        app.segmentedControls["brand_control"].buttons["Amex"].tap()
        XCTAssertEqual(app.staticTexts["cvv_label"].label, "CVV (4 digits)")
        XCTAssertFalse(app.buttons["pay_button"].isEnabled, "3 digits no longer fit an Amex CVV")
        XCTAssertTrue(app.staticTexts["debug_label"].label.contains("expects=[4]  brand=AMEX"))

        enter("4", into: cvv)
        dismissKeyboard()
        XCTAssertEqual(app.otherElements["cvv_container"].value as? String, "valid")
        XCTAssertTrue(app.buttons["pay_button"].isEnabled)

        app.segmentedControls["brand_control"].buttons["Visa"].tap()
        XCTAssertEqual(app.staticTexts["cvv_label"].label, "CVV (3 digits)")
        XCTAssertFalse(app.buttons["pay_button"].isEnabled, "4 digits no longer fit a Visa CVV")
    }

    /// The mode control rebuilds the screen — the manual way to try the
    /// CVV-only form without a launch argument.
    func testModeControlSwitchesBetweenFullAndCVVOnly() {
        launch()
        XCTAssertTrue(app.textFields["pan_field"].waitForExistence(timeout: 5))

        app.segmentedControls["mode_control"].buttons["CVV only"].tap()
        XCTAssertTrue(app.secureTextFields["cvv_field"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.textFields["pan_field"].exists, "CVV-only mode mounts no PAN field")
        XCTAssertFalse(app.textFields["expiry_field"].exists)
        XCTAssertFalse(app.buttons["pay_button"].isEnabled)

        app.segmentedControls["mode_control"].buttons["Full form"].tap()
        XCTAssertTrue(app.textFields["pan_field"].waitForExistence(timeout: 3), "the full form comes back")
        XCTAssertTrue(app.textFields["expiry_field"].exists)
    }

    func testClearResetsForm() {
        launch(tokenizeSuccess: true)
        fillValidCard()
        XCTAssertTrue(app.buttons["pay_button"].isEnabled)
        app.buttons["clear_button"].tap()
        XCTAssertFalse(app.buttons["pay_button"].isEnabled)
        XCTAssertEqual(app.otherElements["pan_container"].value as? String, "empty")
    }
}
