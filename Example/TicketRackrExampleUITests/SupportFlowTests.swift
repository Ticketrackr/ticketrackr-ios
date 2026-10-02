import XCTest

/// Support in a real app, against TicketRackr running on this Mac with a customer who has a request with a file
/// (scripts/embedded-support-test-host.mjs). Screenshots are kept in the test results.
final class SupportFlowTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launchEnvironment["SUPPORT_LINK_URL"] = ProcessInfo.processInfo.environment["SUPPORT_LINK_URL"] ?? "http://localhost:4390/support-link"
        app.launch()
    }

    func testHelpOpensSupportWithTheRequestItsFileAReplyAndClose() {
        app.buttons["Help"].tap()
        let web = app.webViews.firstMatch
        let request = web.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Receipt from the app'")).firstMatch
        XCTAssertTrue(request.waitForExistence(timeout: 30), "support signs in from the link")
        keep("1 support")

        request.tap()
        let file = web.links.matching(NSPredicate(format: "label CONTAINS 'receipt.png'")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 15), "the request opens with its file")
        keep("2 request")

        // A file opens in a sheet over support, with Back.
        file.tap()
        let back = app.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 15), "the file opens over support")
        sleep(2)
        keep("3 file")
        back.tap()
        XCTAssertTrue(file.waitForExistence(timeout: 10), "support is as it was")

        // The reply box stays above the keyboard, and the reply is sent.
        let reply = web.textViews.firstMatch
        reply.tap()
        reply.typeText("Thanks, the receipt is attached above.")
        keep("4 typing")
        web.buttons["Send reply"].tap()
        let sent = web.staticTexts.matching(NSPredicate(format: "label CONTAINS 'the receipt is attached above'")).firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 15), "the reply is sent")
        // Sending is done when the reply box is empty again (support is busy until then).
        let empty = NSPredicate(format: "value == '' OR value BEGINSWITH 'Write a reply'")
        expectation(for: empty, evaluatedWith: reply)
        waitForExpectations(timeout: 15)
        keep("5 sent")

        // Close in support closes the sheet.
        web.buttons["Close support"].tap()
        XCTAssertTrue(app.staticTexts["log"].waitForExistence(timeout: 10))
        let closed = NSPredicate(format: "label CONTAINS 'sheet closed'")
        expectation(for: closed, evaluatedWith: app.staticTexts["log"])
        waitForExpectations(timeout: 10)
        keep("6 closed")
    }

    func testSupportAsAScreenTellsTheAppItsReady() {
        app.buttons["Support as a screen"].tap()
        let request = app.webViews.firstMatch.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Receipt from the app'")).firstMatch
        XCTAssertTrue(request.waitForExistence(timeout: 30))
        app.webViews.firstMatch.buttons["Close support"].tap()
        let told = NSPredicate(format: "label CONTAINS 'ready' AND label CONTAINS 'unread 0'")
        expectation(for: told, evaluatedWith: app.staticTexts["log"])
        waitForExpectations(timeout: 10)
        keep("7 screen events")
    }

    func testAnEndedSessionRenewsItself() throws {
        app.buttons["Support as a screen"].tap()
        let request = app.webViews.firstMatch.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Receipt from the app'")).firstMatch
        XCTAssertTrue(request.waitForExistence(timeout: 30))
        // The company ends the customer's sessions (as signing out does): support gets a new link and is ready again.
        let endpoint = ProcessInfo.processInfo.environment["SUPPORT_LINK_URL"] ?? "http://localhost:4390/support-link"
        var revoke = URLRequest(url: URL(string: endpoint.replacingOccurrences(of: "/support-link", with: "/revoke"))!)
        revoke.httpMethod = "POST"
        let done = expectation(description: "sessions ended")
        URLSession.shared.dataTask(with: revoke) { _, _, _ in done.fulfill() }.resume()
        wait(for: [done], timeout: 10)
        // Support notices on its next check, then signs in again with a new link.
        sleep(25)
        XCTAssertTrue(request.waitForExistence(timeout: 30), "support is back")
        keep("8 renewed")
        app.webViews.firstMatch.buttons["Close support"].tap()
        expectation(for: NSPredicate(format: "label MATCHES '.*ready.*ready.*'"), evaluatedWith: app.staticTexts["log"])
        waitForExpectations(timeout: 15)
    }

    private func keep(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
