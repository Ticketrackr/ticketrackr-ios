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
        case "unread": return count(message["count"]).map(SupportEvent.unread)
        default: return nil
        }
    }

    // A whole number of zero or more; not text, a fraction or true/false (which JSON numbers also decode as).
    private static func count(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double >= 0, double == double.rounded(), double <= Double(Int.max) else { return nil }
        return number.intValue
    }
}
