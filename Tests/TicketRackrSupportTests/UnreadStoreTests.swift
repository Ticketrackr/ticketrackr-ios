import Foundation
import XCTest
@testable import TicketRackrSupport

/// The Help button's badge kept across launches (sdks/protocol, section 7), each test in a UserDefaults of its own and
/// with TicketRackr's answers made up.
final class UnreadStoreTests: XCTestCase {
    private let origin = "https://ticketrackr.com"
    private let token = "trk_unread_" + String(repeating: "a", count: 43)
    private let next = "trk_unread_" + String(repeating: "b", count: 43)
    private var suite = ""
    private var defaults: UserDefaults!
    private var store: UnreadStore!

    override func setUpWithError() throws {
        suite = "com.ticketrackr.support.tests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        store = UnreadStore(defaults: defaults)
        Stub.answer = nil
        Stub.asked = []
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testACountBeforeItsTokenIsKeptWithIt() {
        // Support reports the count first, then asks for its token.
        store.report(count: 2, origin: origin)
        XCTAssertNil(store.current(now: 1000))
        store.keep(token: token, expiresAt: 5000, origin: origin)
        XCTAssertEqual(store.current(now: 1000), UnreadBadge(origin: origin, token: token, expiresAt: 5000, count: 2))
    }

    func testANewTokenReplacesTheOldOneAndOutlastsTheLaunch() {
        store.keep(token: token, expiresAt: 5000, origin: origin)
        store.report(count: 3, origin: origin)
        store.keep(token: next, expiresAt: 6000, origin: origin)
        // The next launch reads it from the same UserDefaults.
        XCTAssertEqual(UnreadStore(defaults: defaults).current(now: 1000), UnreadBadge(origin: origin, token: next, expiresAt: 6000, count: 3))
    }

    func testATokenBeforeAnyCountInALaunchKeepsTheCountAlreadyKept() {
        store.keep(token: token, expiresAt: 5000, origin: origin)
        store.report(count: 4, origin: origin)
        let relaunched = UnreadStore(defaults: defaults)
        relaunched.keep(token: next, expiresAt: 6000, origin: origin)
        XCTAssertEqual(relaunched.current(now: 1000)?.count, 4)
    }

    func testCountsAreKeptOnlyWithTheirSupportPagesToken() {
        store.keep(token: token, expiresAt: 5000, origin: origin)
        store.report(count: 1, origin: origin)
        store.report(count: 9, origin: "http://localhost:3219")
        XCTAssertEqual(store.current(now: 1000)?.count, 1)
    }

    func testSignOutForgetsTheTokenAndEveryCount() {
        store.report(count: 2, origin: origin)
        store.keep(token: token, expiresAt: 5000, origin: origin)
        store.signOut()
        XCTAssertNil(store.current(now: 1000))
        XCTAssertNil(defaults.object(forKey: "com.ticketrackr.support.unread"))
        // The next person to open support doesn't get the last one's count.
        store.keep(token: next, expiresAt: 5000, origin: origin)
        XCTAssertEqual(store.current(now: 1000)?.token, next)
        XCTAssertNil(store.current(now: 1000)?.count)
    }

    func testSignOutClearsHelpButtonsEvenWithNothingKept() {
        // A Help button may show what support reported before its token came (or when none came).
        let told = expectation(forNotification: UnreadStore.changed, object: store)
        store.report(count: 2, origin: origin)
        store.signOut()
        wait(for: [told], timeout: 5)
    }

    func testAnExpiredTokenIsForgotten() {
        store.keep(token: token, expiresAt: 2000, origin: origin)
        XCTAssertNotNil(store.current(now: 1999))
        XCTAssertNil(store.current(now: 2000))
        XCTAssertNil(store.current(now: 1000), "forgotten, not just hidden")
    }

    func testAnswersShowTheCountForgetTheTokenOrKeepTheBadge() throws {
        store.report(count: 2, origin: origin)
        store.keep(token: token, expiresAt: 5000, origin: origin)
        var asked = try XCTUnwrap(store.current(now: 1000))
        XCTAssertEqual(store.apply(.keep, asked: asked), 2)
        XCTAssertEqual(store.apply(.count(4), asked: asked), 4)
        asked = try XCTUnwrap(store.current(now: 1000))
        XCTAssertEqual(asked.count, 4)
        XCTAssertNil(store.apply(.forget, asked: asked))
        XCTAssertNil(store.current(now: 1000))
    }

    func testAnAnswerToAnOutOfDateCheckChangesNothing() throws {
        store.keep(token: token, expiresAt: 5000, origin: origin)
        let asked = try XCTUnwrap(store.current(now: 1000))
        // Support opened again while the check was out: its new token stays.
        store.report(count: 0, origin: origin)
        store.keep(token: next, expiresAt: 6000, origin: origin)
        XCTAssertEqual(store.apply(.forget, asked: asked), 0)
        XCTAssertEqual(store.current(now: 1000)?.token, next)
        // The app signed out while a check was out: nothing comes back.
        let again = try XCTUnwrap(store.current(now: 1000))
        store.signOut()
        XCTAssertNil(store.apply(.count(5), asked: again))
        XCTAssertNil(store.current(now: 1000))
    }

    func testAskingSendsTheTokenAndKeepsTheAnswer() async throws {
        store.keep(token: token, expiresAt: UnreadStore.now() + 60_000, origin: origin)
        Stub.answer = (200, #"{"unread": 3}"#)
        let count = await store.refresh(session: Stub.session)
        XCTAssertEqual(count, 3)
        let request = try XCTUnwrap(Stub.asked.last)
        XCTAssertEqual(request.url?.absoluteString, "https://ticketrackr.com/api/support/unread")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
        // No connection: the count stays.
        Stub.answer = nil
        let offline = await store.refresh(session: Stub.session)
        XCTAssertEqual(offline, 3)
        // Refused: the token and its count are forgotten.
        Stub.answer = (401, "{}")
        let refused = await store.refresh(session: Stub.session)
        XCTAssertNil(refused)
        XCTAssertNil(store.current())
    }

    func testAnAutomaticCheckWithNothingToAskDoesntUseUpTheMinute() async {
        let nothing = await store.refresh(automatic: true, session: Stub.session)
        XCTAssertNil(nothing)
        XCTAssertTrue(Stub.asked.isEmpty)
        store.keep(token: token, expiresAt: UnreadStore.now() + 60_000, origin: origin)
        Stub.answer = (200, #"{"unread": 4}"#)
        let first = await store.refresh(automatic: true, session: Stub.session)
        XCTAssertEqual(first, 4)
        // Within the minute, an automatic check doesn't ask: the badge stays as it was.
        Stub.answer = (200, #"{"unread": 5}"#)
        let second = await store.refresh(automatic: true, session: Stub.session)
        XCTAssertEqual(second, 4)
        XCTAssertEqual(Stub.asked.count, 1)
        // The app's own call always asks.
        let own = await store.refresh(session: Stub.session)
        XCTAssertEqual(own, 5)
    }
}

/// TicketRackr, made up: answers every request with `answer` (no connection when nil) and keeps what it was asked.
private final class Stub: URLProtocol {
    static var answer: (status: Int, body: String)?
    static var asked: [URLRequest] = []
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        return URLSession(configuration: configuration)
    }()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Stub.asked.append(request)
        guard let answer = Stub.answer, let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(answer.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
