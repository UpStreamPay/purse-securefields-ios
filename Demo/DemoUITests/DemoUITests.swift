import XCTest
import UIKit

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

    private func dismissKeyboard() {
        // Tap the nav bar title area to reliably resign first responder
        app.navigationBars.firstMatch.tap()
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
        let pan = app.textFields["pan_field"]
        pan.tap()
        pan.typeText("4111111111111112") // bad Luhn
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

    func testClearResetsForm() {
        launch(tokenizeSuccess: true)
        fillValidCard()
        XCTAssertTrue(app.buttons["pay_button"].isEnabled)
        app.buttons["clear_button"].tap()
        XCTAssertFalse(app.buttons["pay_button"].isEnabled)
        XCTAssertEqual(app.otherElements["pan_container"].value as? String, "empty")
    }

    // MARK: - TEMPORARY: bug gallery screenshot capture (to be removed before commit)

    private func attachScreenshot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func button(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    private func tapButton(_ app: XCUIApplication, containing text: String, wait: TimeInterval = 3) {
        let b = button(app, containing: text)
        XCTAssertTrue(b.waitForExistence(timeout: wait), "Button containing '\(text)' not found")
        b.tap()
    }

    private func eventLogText(_ app: XCUIApplication) -> String {
        (app.textViews.firstMatch.value as? String) ?? ""
    }

    /// Bug #8 needs a manual tap on the "Carte Bancaire" brand chip (a plain UIControl with no
    /// accessibility identifier, rendered as an image so no readable label either). We sweep a
    /// handful of x-offsets from the right edge of the PAN field's row, where the chip stack is
    /// right-aligned, and stop as soon as the event log shows the CB selection actually landed.
    private func tapCarteBancaireChip(_ app: XCUIApplication) {
        let panField = app.textFields.element(boundBy: 0)
        guard panField.waitForExistence(timeout: 3) else { return }
        let frame = panField.frame
        let midY = frame.midY
        let screenWidth = app.windows.element(boundBy: 0).frame.width
        var dx: CGFloat = 12
        while dx <= 110 {
            let point = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: screenWidth - dx, dy: midY))
            point.tap()
            Thread.sleep(forTimeInterval: 0.3)
            if eventLogText(app).contains("CARTE_BANCAIRE") { return }
            dx += 6
        }
    }

    func testZZZCaptureBugGalleryScreenshots() {
        app.launch() // no --uitesting arg => lands on BugListViewController (the bug gallery home)

        XCTAssertTrue(app.tables.cells.element(boundBy: 0).waitForExistence(timeout: 5))
        attachScreenshot("home")

        for row in 0..<10 {
            let number = row + 1
            let cell = app.tables.cells.element(boundBy: row)
            XCTAssertTrue(cell.waitForExistence(timeout: 5), "Cell for bug #\(number) not found")
            cell.tap()
            XCTAssertTrue(app.navigationBars["Bug #\(number)"].waitForExistence(timeout: 5), "Screen for bug #\(number) didn't load")

            switch number {
            case 1:
                let field = app.textFields.element(boundBy: 0)
                XCTAssertTrue(field.waitForExistence(timeout: 3))
                field.tap()
                field.typeText("1228")
                app.navigationBars.firstMatch.tap() // dismiss keyboard
                Thread.sleep(forTimeInterval: 1.0)
            case 2:
                tapButton(app, containing: "Remplir un PAN Oney")
                Thread.sleep(forTimeInterval: 1.0)
            case 3:
                tapButton(app, containing: "1. Remplir carte Oney")
                Thread.sleep(forTimeInterval: 1.0)
                tapButton(app, containing: "2. Envoyer (submit)")
                Thread.sleep(forTimeInterval: 1.0)
            case 4:
                tapButton(app, containing: "Taper 8 chiffres d'un BIN Oney")
                Thread.sleep(forTimeInterval: 2.0)
            case 5:
                tapButton(app, containing: "Remplir une Mastercard valide")
                Thread.sleep(forTimeInterval: 0.5)
                tapButton(app, containing: "Envoyer (submit)")
                Thread.sleep(forTimeInterval: 1.0)
            case 6:
                tapButton(app, containing: "Reproduire automatiquement")
                Thread.sleep(forTimeInterval: 0.8)
            case 7:
                tapButton(app, containing: "1. Remplir carte co-badgée")
                Thread.sleep(forTimeInterval: 1.0)
                tapButton(app, containing: "2. Basculer sur Carte Bancaire")
                Thread.sleep(forTimeInterval: 0.8)
            case 8:
                tapButton(app, containing: "1. Taper 8 chiffres (co-badgé)")
                Thread.sleep(forTimeInterval: 1.0)
                tapCarteBancaireChip(app)
                Thread.sleep(forTimeInterval: 0.5)
                tapButton(app, containing: "2. Effacer 1 chiffre")
                Thread.sleep(forTimeInterval: 2.5)
            case 9:
                tapButton(app, containing: "1. Remplir + envoyer une carte Oney")
                Thread.sleep(forTimeInterval: 2.0)
                let cvvField = app.textFields.element(boundBy: 1)
                if cvvField.waitForExistence(timeout: 2) {
                    cvvField.tap()
                    Thread.sleep(forTimeInterval: 0.8)
                }
            case 10:
                tapButton(app, containing: "Simuler la saisie")
                Thread.sleep(forTimeInterval: 7.5)
            default:
                break
            }

            attachScreenshot(String(format: "bug%02d", number))

            let backButton = app.navigationBars.buttons.element(boundBy: 0)
            XCTAssertTrue(backButton.waitForExistence(timeout: 5))
            backButton.tap()
            XCTAssertTrue(app.tables.cells.element(boundBy: 0).waitForExistence(timeout: 5), "Didn't return to bug list after bug #\(number)")
        }
    }
}
