@_exported import TicketRackrSupportCore

#if os(iOS)
import UIKit

/// TicketRackr support in your app.
public enum TicketRackr {
    /// Shows support in a sheet over `presenter`, with a Close button. Returns it, to set `onReady` or `onClose`.
    @MainActor
    @discardableResult
    public static func presentSupport(
        from presenter: UIViewController,
        getSupportLink: @escaping GetSupportLink,
        options: SupportOptions = SupportOptions(),
        onUnreadChange: ((Int) -> Void)? = nil
    ) -> TicketRackrSupportViewController {
        let support = TicketRackrSupportViewController(getSupportLink: getSupportLink, options: options, closable: true)
        support.onUnreadChange = onUnreadChange
        support.modalPresentationStyle = .pageSheet
        presenter.present(support, animated: true)
        return support
    }

    /// The customer's unread replies, for a badge of your own (a tab bar, a menu), or nil when they aren't known, such
    /// as before support has opened on this device or after `signOut()`. Asks TicketRackr each time; without a
    /// connection, it answers the last count known. `SupportButton` keeps its own badge without this.
    public static func unreadCount() async -> Int? {
        await UnreadStore.shared.refresh()
    }

    /// Forgets the unread count and what it's asked with, until support opens again. Call it when your app's user signs
    /// out, so the next person on this device doesn't see their count.
    public static func signOut() {
        UnreadStore.shared.signOut()
    }
}
#endif
