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
                    language: options["language"] as? String
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

    func testWordsFollowTheLanguage() {
        XCTAssertEqual(SupportWords.forLanguage("es").help, "Ayuda")
        XCTAssertEqual(SupportWords.forLanguage("pt-BR").back, "Voltar")
        XCTAssertEqual(SupportWords.forLanguage("ja").help, "Help")
    }

    private func list(_ key: String) throws -> [[String: Any]] {
        try XCTUnwrap(cases[key] as? [[String: Any]])
    }
}
