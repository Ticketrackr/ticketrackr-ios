import Foundation

/// Where a link followed inside support goes (sdks/protocol, section 4).
public enum SupportDestination: String, Equatable, Sendable {
    /// The support page itself: it stays in support.
    case support
    /// One of support's files (an attachment).
    case file
    /// Another TicketRackr page, like the status page or a help article.
    case page
    /// Another site, or a mail or phone link.
    case outside

    public static func of(_ url: String, origin: String) -> SupportDestination {
        guard SupportOrigin.of(url) == origin, let parts = URLComponents(string: url) else { return .outside }
        if parts.path == "/support" { return .support }
        return parts.path.range(of: "^/api/support/tickets/[A-Za-z0-9_-]+/attachments/[A-Za-z0-9_-]+/download$", options: .regularExpression) != nil ? .file : .page
    }
}

/// Origins: scheme, host and port, as browsers compare them.
public enum SupportOrigin {
    /// An address's origin, like `https://ticketrackr.com`, or nil for one without a host (`about:blank`, `mailto:`).
    public static func of(_ url: String) -> String? {
        guard let parts = URLComponents(string: url), let scheme = parts.scheme?.lowercased(), let host = parts.host?.lowercased(), !host.isEmpty else {
            return nil
        }
        let standard = (scheme == "https" && parts.port == 443) || (scheme == "http" && parts.port == 80)
        guard let port = parts.port, !standard else { return "\(scheme)://\(host)" }
        return "\(scheme)://\(host):\(port)"
    }

    /// Whether a message came from the support page. Web views give the page's address or only its origin.
    public static func isSupport(_ url: String?, origin: String) -> Bool {
        guard let url else { return false }
        return of(url) == origin
    }
}

/// When the session keeps ending (twice in 30 seconds), support stops getting new links and offers Try again.
public final class ReconnectGuard {
    private let window: TimeInterval
    private let limit: Int
    private var recent: [TimeInterval] = []

    public init(window: TimeInterval = 30, limit: Int = 2) {
        self.window = window
        self.limit = limit
    }

    /// Whether to get a new link now (`now` in seconds).
    public func allow(now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        while let first = recent.first, now - first > window { recent.removeFirst() }
        guard recent.count < limit else { return false }
        recent.append(now)
        return true
    }
}
