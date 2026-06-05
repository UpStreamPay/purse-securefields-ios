import XCTest

final class DemoUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    // MARK: - Launch helpers

    private func launch(tokenizeSuccess: Bool? = nil) {
        app.launchArguments.append("--uitesting")
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
    }

    private func fillValidCard() {
        app.textFields["pan_field"].tap()
        app.textFields["pan_field"].typeText("4111111111111111")

        app.textFields["expiry_field"].tap()
        app.textFields["expiry_field"].typeText("1230")

        app.textFields["holder_field"].tap()
        app.textFields["holder_field"].typeText("John Doe")

        app.secureTextFields["cvv_field"].tap()
        app.secureTextFields["cvv_field"].typeText("123")

        // Dismiss keyboard so focus is removed (border states update)
        app.swipeDown()
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
        let pan = app.textFields["pan_field"]
        pan.tap()
        pan.typeText("4111111111111112") // bad Luhn
        app.swipeDown() // unfocus
        XCTAssertEqual(app.otherElements["pan_container"].value as? String, "invalid")
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

    func testClearResetsForm() {
        launch(tokenizeSuccess: true)
        fillValidCard()
        XCTAssertTrue(app.buttons["pay_button"].isEnabled)
        app.buttons["clear_button"].tap()
        XCTAssertFalse(app.buttons["pay_button"].isEnabled)
        XCTAssertEqual(app.otherElements["pan_container"].value as? String, "empty")
    }
}
