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
}
#endif
