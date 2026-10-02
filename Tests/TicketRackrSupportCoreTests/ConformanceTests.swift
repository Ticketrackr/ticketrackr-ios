import Foundation
import XCTest
@testable import TicketRackrSupportCore

/// The protocol cases every TicketRackr SDK passes (sdks/protocol/conformance.json, copied here).
final class ConformanceTests: XCTestCase {
    private var cases: [String: Any] = [:]

    override func setUpWithError() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "conformance", withExtension: "json"))
        cases = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func testTheAddressSupportIsShownAt() throws {
        for item in try list("frameUrl") {
            let name = item["name"] as! String
            let options = item["options"] as! [String: Any]
            let url = try SupportAddress.frameURL(
                link: item["link"] as! String,
                options: SupportOptions(
                    requestType: options["requestType"] as? String,
                    subject: options["subject"] as? String,
                    fields: options["fields"] as? [String: String] ?? [:],
                    language: options["language"] as? String,
                    ticket: options["ticket"] as? String
                ),
                closable: options["closable"] as? Bool ?? false,
                edges: options["edges"] as? Bool ?? false,
                load: options["load"] as? Int ?? 0
            )
            let expect = item["expect"] as! [String: Any]
            let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            XCTAssertEqual("\(parts.scheme!)://\(parts.host!)\(parts.port.map { ":\($0)" } ?? "")\(parts.path)", expect["base"] as? String, name)
            XCTAssertEqual(parts.fragment, expect["fragment"] as? String, name)
            var params: [String: String] = [:]
            for query in parts.queryItems ?? [] { params[query.name] = query.value ?? "" }
            XCTAssertEqual(params, expect["params"] as? [String: String], name)
        }
    }

    func testOnlyTicketRackrSupportLinksAreShown() throws {
        for link in try XCTUnwrap(cases["invalidLinks"] as? [String]) {
            XCTAssertThrowsError(try SupportAddress.frameURL(link: link), link) { error in
                XCTAssertTrue(error.localizedDescription.contains("getSupportLink"), link)
            }
        }
    }

    func testOnlyThePagesOwnEventsAreRead() throws {
        for item in try list("events") {
            let data = item["data"] as! String
            let expected: SupportEvent? = (item["expect"] as? [String: Any]).map { expect in
                switch expect["event"] as! String {
                case "ready": return .ready
                case "close": return .close
                case "session-ended": return .sessionEnded
                case "unread-token": return .unreadToken(token: expect["token"] as! String, expiresAt: (expect["expiresAt"] as! NSNumber).int64Value)
                default: return .unread(expect["count"] as! Int)
                }
            }
            XCTAssertEqual(SupportEvent.read(data), expected, data)
        }
    }

    func testMessagesAreMatchedByOrigin() throws {
        for item in try list("origins") {
            XCTAssertEqual(SupportOrigin.isSupport(item["url"] as? String, origin: item["origin"] as! String), item["expect"] as! Bool, item["url"] as! String)
        }
    }

    func testWhereLinksGo() throws {
        for item in try list("destinations") {
            XCTAssertEqual(SupportDestination.of(item["url"] as! String, origin: item["origin"] as! String).rawValue, item["expect"] as! String, item["url"] as! String)
        }
    }

    func testASessionThatKeepsEndingIsntReconnectedForever() throws {
        let reconnect = try XCTUnwrap(cases["reconnect"] as? [String: Any])
        let guardian = ReconnectGuard(window: (reconnect["windowMs"] as! Double) / 1000, limit: reconnect["limit"] as! Int)
        for call in reconnect["calls"] as! [[String: Any]] {
            XCTAssertEqual(guardian.allow(now: (call["at"] as! Double) / 1000), call["expect"] as! Bool, "at \(call["at"]!)")
        }
    }

    func testTheUnreadCountIsAskedForWithItsToken() throws {
        for item in try unread("requests") as! [[String: Any]] {
            let expect = item["expect"] as! [String: Any]
            let request = try XCTUnwrap(SupportUnread.request(origin: item["origin"] as! String, token: item["token"] as! String))
            XCTAssertEqual(request.url?.absoluteString, expect["url"] as? String)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), expect["authorization"] as? String)
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertFalse(request.httpShouldHandleCookies)
        }
    }

    func testEachAnswerShowsTheCountForgetsTheTokenOrKeepsTheBadge() throws {
        for item in try unread("answers") as! [[String: Any]] {
            let expect = item["expect"] as! [String: Any]
            let expected: UnreadAnswer
            switch expect["result"] as! String {
            case "count": expected = .count(expect["count"] as! Int)
            case "forget": expected = .forget
            default: expected = .keep
            }
            let body = item["body"] as! String
            XCTAssertEqual(UnreadAnswer.of(status: item["status"] as! Int, body: Data(body.utf8)), expected, "\(item["status"]!) \(body)")
        }
    }

    func testTheBadgeIsCheckedAtMostOnceAMinute() throws {
        let checks = try unread("guard") as! [String: Any]
        let guardian = UnreadGuard(interval: (checks["intervalMs"] as! Double) / 1000)
        for call in checks["calls"] as! [[String: Any]] {
            XCTAssertEqual(guardian.allow(now: (call["at"] as! Double) / 1000), call["expect"] as! Bool, "at \(call["at"]!)")
        }
    }

    func testAnExpiredTokenIsntUsed() throws {
        for item in try unread("expiry") as! [[String: Any]] {
            let expiresAt = (item["expiresAt"] as! NSNumber).int64Value
            let now = (item["now"] as! NSNumber).int64Value
            XCTAssertEqual(SupportUnread.isUsable(expiresAt: expiresAt, now: now), item["expect"] as! Bool, "\(now) for \(expiresAt)")
        }
    }

    func testWordsFollowTheLanguage() {
        XCTAssertEqual(SupportWords.forLanguage("es").help, "Ayuda")
        XCTAssertEqual(SupportWords.forLanguage("pt-BR").back, "Voltar")
        XCTAssertEqual(SupportWords.forLanguage("ja").help, "Help")
    }

    private func list(_ key: String) throws -> [[String: Any]] {
        try XCTUnwrap(cases[key] as? [[String: Any]])
    }

    // One part of the unread cases (section 7).
    private func unread(_ key: String) throws -> Any {
        try XCTUnwrap((cases["unread"] as? [String: Any])?[key], key)
    }
}
