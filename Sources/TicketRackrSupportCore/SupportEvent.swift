import Foundation

/// What the support page tells the app (sdks/protocol, section 3). Events only, never customer data.
public enum SupportEvent: Equatable, Sendable {
    /// Support has loaded and signed in.
    case ready
    /// The customer pressed Close.
    case close
    /// The session expired or was revoked: support needs a new link.
    case sessionEnded
    /// The customer's unread replies, whenever the number changes.
    case unread(Int)
    /// A token for the Help button's badge while support is closed (section 7), and when it expires, in milliseconds
    /// since 1970.
    case unreadToken(token: String, expiresAt: Int64)

    /// The event in a message from the page (a JSON string), or nil for anything else.
    public static func read(_ data: String) -> SupportEvent? {
        guard let bytes = data.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed]),
              let message = value as? [String: Any],
              message["source"] as? String == "ticketrackr-support",
              let event = message["event"] as? String else { return nil }
        switch event {
        case "ready": return .ready
        case "close": return .close
        case "session-ended": return .sessionEnded
        case "unread":
            guard let count = wholeNumber(message["count"]), count >= 0 else { return nil }
            return .unread(Int(count))
        case "unread-token":
            guard let token = message["token"] as? String, SupportUnread.isToken(token),
                  let expiresAt = wholeNumber(message["expiresAt"]), expiresAt > 0 else { return nil }
            return .unreadToken(token: token, expiresAt: expiresAt)
        default: return nil
        }
    }
}

/// A whole number from JSON; not text, a fraction or true/false (which JSON numbers also decode as). Only up to
/// JavaScript's largest exact integer, like the page's own numbers.
func wholeNumber(_ value: Any?) -> Int64? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
    let double = number.doubleValue
    guard double == double.rounded(), abs(double) <= 9_007_199_254_740_991 else { return nil }
    return number.int64Value
}
