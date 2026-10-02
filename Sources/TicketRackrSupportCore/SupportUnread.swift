import Foundation

/// The Help button's badge while support is closed (sdks/protocol, section 7). Each time support opens, the page hands
/// the app a token that reads the customer's unread replies and nothing else; the app asks with it until it expires or
/// is refused.
public enum SupportUnread {
    /// Whether `token` is an unread token: `trk_unread_` and 43 letters, digits, `-` or `_`.
    public static func isToken(_ token: String) -> Bool {
        // All of it: on some iOS versions `$` also matches before a final line break.
        token.range(of: "^trk_unread_[A-Za-z0-9_-]{43}$", options: .regularExpression) == token.startIndex..<token.endIndex
    }

    /// The request for the customer's unread replies: `GET <origin>/api/support/unread` with the token, its only
    /// credential (no cookie, nothing cached).
    public static func request(origin: String, token: String) -> URLRequest? {
        guard let url = URL(string: origin + "/api/support/unread") else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// Whether a token that expires at `expiresAt` is still used `now`, both in milliseconds since 1970.
    public static func isUsable(expiresAt: Int64, now: Int64) -> Bool {
        now < expiresAt
    }
}

/// What an answer to the unread request means for the badge.
public enum UnreadAnswer: Equatable, Sendable {
    /// The customer's unread replies: the badge shows them (nothing for 0).
    case count(Int)
    /// The token was refused: forget it, so the badge shows nothing until support opens again.
    case forget
    /// Anything else (another status, a bad body, no connection): the badge stays as it was, and asks again next time.
    case keep

    /// The meaning of an answer, from its HTTP status and body.
    public static func of(status: Int, body: Data) -> UnreadAnswer {
        if status == 401 || status == 403 { return .forget }
        guard status == 200,
              let value = try? JSONSerialization.jsonObject(with: body),
              let answer = value as? [String: Any],
              let count = wholeNumber(answer["unread"]), count >= 0 else { return .keep }
        return .count(Int(count))
    }
}

/// The badge's own checks (when the Help button appears, when the app comes back): at most one a minute, the first
/// always. Every check in the app shares one.
public final class UnreadGuard {
    private let interval: TimeInterval
    private var last: TimeInterval?

    public init(interval: TimeInterval = 60) {
        self.interval = interval
    }

    /// Whether to check now (`now` in seconds).
    public func allow(now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        // A clock set back doesn't hold checks up.
        if let last, now >= last, now - last < interval { return false }
        last = now
        return true
    }
}
