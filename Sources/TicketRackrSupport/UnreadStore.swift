import Foundation
import TicketRackrSupportCore

/// What the Help button's badge counts with while support is closed (sdks/protocol, section 7): the latest unread
/// token, the origin of the support page that gave it, and the last count known.
struct UnreadBadge: Codable, Equatable {
    var origin: String
    var token: String
    /// When the token stops working, in milliseconds since 1970.
    var expiresAt: Int64
    /// The last count known, or nil before there is one.
    var count: Int?
}

/// The badge, kept in UserDefaults across launches. One per app: a new token replaces the old one. Safe to use from any
/// thread.
final class UnreadStore: @unchecked Sendable {
    /// The app's own.
    static let shared = UnreadStore(defaults: .standard)
    /// Posted on the main thread after the badge changes.
    static let changed = Notification.Name("TicketRackrSupportUnreadChanged")
    /// Asks without the app's cookies or cache.
    static let session = URLSession(configuration: .ephemeral)

    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()
    // Every automatic check in the app shares it: at most one a minute.
    private let checks = UnreadGuard()
    // The count support last reported in this launch, for a token that arrives after it (support sends the count
    // first, then asks for its token).
    private var reported: Int?

    init(defaults: UserDefaults, key: String = "com.ticketrackr.support.unread") {
        self.defaults = defaults
        self.key = key
    }

    /// Now, in milliseconds since 1970.
    static func now() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    /// The badge while its token works; an expired one is forgotten.
    func current(now: Int64 = UnreadStore.now()) -> UnreadBadge? {
        var badge: UnreadBadge?
        change { stored in
            guard let stored, SupportUnread.isUsable(expiresAt: stored.expiresAt, now: now) else { return nil }
            badge = stored
            return stored
        }
        return badge
    }

    /// Keeps a new token from the support page at `origin`, replacing any earlier one, with the count support reported,
    /// or else the count already kept.
    func keep(token: String, expiresAt: Int64, origin: String) {
        change { stored in
            UnreadBadge(origin: origin, token: token, expiresAt: expiresAt, count: reported ?? stored?.count)
        }
    }

    /// The count support reports whenever it changes: kept with the token from the same support page, and remembered
    /// for a token still to come.
    func report(count: Int, origin: String) {
        change { stored in
            reported = count
            guard var stored, stored.origin == origin else { return stored }
            stored.count = count
            return stored
        }
    }

    /// Forgets the token and every count: the app's user signed out. Help buttons clear their badges even when nothing
    /// was kept (they may show what support reported).
    func signOut() {
        change(always: true) { _ in
            reported = nil
            return nil
        }
    }

    /// Asks TicketRackr for the count with the stored token and keeps the answer. `automatic` checks (not the app's
    /// own) share the guard, and only those that ask count toward it. Returns the count to show, or nil when none is
    /// known.
    @discardableResult
    func refresh(automatic: Bool = false, session: URLSession = UnreadStore.session) async -> Int? {
        guard let asked = current() else { return nil }
        guard let request = SupportUnread.request(origin: asked.origin, token: asked.token) else { return asked.count }
        if automatic, !locked({ checks.allow() }) { return asked.count }
        let answer: UnreadAnswer
        do {
            let (body, response) = try await session.data(for: request)
            answer = UnreadAnswer.of(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: body)
        } catch {
            // No connection: ask again next time.
            answer = .keep
        }
        return apply(answer, asked: asked)
    }

    /// Keeps an answer to a check made with `asked`, unless the badge changed meanwhile (support opened, the app
    /// signed out): then the answer is out of date. Returns the count to show.
    func apply(_ answer: UnreadAnswer, asked: UnreadBadge) -> Int? {
        var shown: Int?
        change { stored in
            guard var stored, stored == asked else {
                shown = stored?.count
                return stored
            }
            switch answer {
            case .count(let count):
                stored.count = count
                shown = count
                return stored
            case .forget:
                return nil
            case .keep:
                shown = stored.count
                return stored
            }
        }
        return shown
    }

    // Reads, changes and writes the badge as one step, and tells the app when it changed (or `always`).
    private func change(always: Bool = false, _ update: (UnreadBadge?) -> UnreadBadge?) {
        let changed: Bool = locked {
            let stored = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(UnreadBadge.self, from: $0) }
            let next = update(stored)
            guard next != stored else { return false }
            if let next, let data = try? JSONEncoder().encode(next) {
                defaults.set(data, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
            return true
        }
        if changed || always {
            DispatchQueue.main.async { NotificationCenter.default.post(name: Self.changed, object: self) }
        }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
