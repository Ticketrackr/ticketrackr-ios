import Foundation

/// What to open in support, in a language: one request type's form, filled in, or one of the customer's requests.
public struct SupportOptions: Equatable, Sendable {
    /// Opens the form for one request type, by its key (Settings → Companies → Case types), such as a report.
    public var requestType: String?
    /// Fills in the request's subject.
    public var subject: String?
    /// Fills in the request type's customer-visible fields, by key.
    public var fields: [String: String]
    /// `en`, `es`, `fr`, `de` or `pt`. The device's language when left out.
    public var language: String?
    /// Opens one of the customer's requests, by its id (`ticket.id` in the ticket.created and ticket.message.created
    /// webhooks), such as from a notification about a reply. Another customer's request isn't opened.
    public var ticket: String?

    public init(requestType: String? = nil, subject: String? = nil, fields: [String: String] = [:], language: String? = nil, ticket: String? = nil) {
        self.requestType = requestType
        self.subject = subject
        self.fields = fields
        self.language = language
        self.ticket = ticket
    }
}

/// A support link that isn't TicketRackr's support page.
public struct SupportLinkError: LocalizedError, Equatable {
    public let errorDescription: String?
    static let refused = SupportLinkError(errorDescription: "TicketRackr: getSupportLink must return the support link from POST /v1/support-portal/links.")
}

/// The address support is shown at (sdks/protocol, section 2).
public enum SupportAddress {
    /// The support link in embedded mode, with what to open. `closable` adds a Close button; `edges` lets the page keep
    /// clear of the status bar and home indicator itself; `load` makes each new link really load.
    public static func frameURL(link: String, options: SupportOptions = SupportOptions(), closable: Bool = false, edges: Bool = false, load: Int = 0) throws -> URL {
        var parts = try supportLink(link)
        var params: [(String, String)] = [("view", "embed")]
        if closable { params.append(("closable", "1")) }
        if edges { params.append(("edges", "1")) }
        if load > 0 { params.append(("load", String(load))) }
        if let language = options.language, !language.isEmpty { params.append(("lang", language)) }
        if let type = options.requestType, !type.isEmpty { params.append(("type", type)) }
        if let subject = options.subject, !subject.isEmpty { params.append(("subject", subject)) }
        for key in options.fields.keys.sorted() where fieldKey(key) {
            params.append(("f.\(key)", String(options.fields[key]!.prefix(500))))
        }
        // Only an id: anything else (a path, a query) is dropped, not sent.
        if let ticket = options.ticket, ticketID(ticket) { params.append(("ticket", ticket)) }
        // A later value replaces an earlier one of the same name; the link's own parameters come first.
        var query = (parts.percentEncodedQueryItems ?? []).filter { item in !params.contains { $0.0 == item.name } }
        query += params.map { URLQueryItem(name: encode($0.0), value: encode($0.1)) }
        parts.percentEncodedQueryItems = query
        guard let url = parts.url else { throw SupportLinkError.refused }
        return url
    }

    /// Only TicketRackr's support page, over https (http only while developing on this machine), with its code.
    static func supportLink(_ link: String) throws -> URLComponents {
        guard let parts = URLComponents(string: link), let scheme = parts.scheme?.lowercased(), let host = parts.host?.lowercased() else {
            throw SupportLinkError.refused
        }
        let local = host == "localhost" || host == "127.0.0.1"
        guard scheme == "https" || (scheme == "http" && local), parts.path == "/support", parts.fragment?.contains("code=") == true else {
            throw SupportLinkError.refused
        }
        return parts
    }

    static func fieldKey(_ key: String) -> Bool {
        key.range(of: "^[a-z][a-z0-9_]{0,63}$", options: .regularExpression) != nil
    }

    static func ticketID(_ id: String) -> Bool {
        id.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil
    }

    // Everything but letters, digits and -._~, so "&", "=", "+" and "#" inside a value stay part of it.
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }
}
