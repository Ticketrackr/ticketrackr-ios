#if os(iOS)
import SwiftUI
import TicketRackrSupportCore

/// The company's support as a SwiftUI view: requests and reports with their forms, the conversation, files, the AI
/// assistant and surveys. It fills the space it's given, reaching under the status bar and home indicator, and keeps
/// clear of them itself.
public struct TicketRackrSupportView: UIViewControllerRepresentable {
    private let getSupportLink: GetSupportLink
    private let options: SupportOptions
    private let closable: Bool
    private let onReady: (() -> Void)?
    private let onUnreadChange: ((Int) -> Void)?
    private let onClose: (() -> Void)?

    /// - Parameters:
    ///   - getSupportLink: Gets a new support link from your server.
    ///   - options: What to open: a request type's form, filled in, in a language.
    ///   - closable: Show a Close button. Without `onClose`, Close dismisses the sheet or screen support is in.
    public init(
        getSupportLink: @escaping GetSupportLink,
        options: SupportOptions = SupportOptions(),
        closable: Bool = false,
        onReady: (() -> Void)? = nil,
        onUnreadChange: ((Int) -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.getSupportLink = getSupportLink
        self.options = options
        self.closable = closable
        self.onReady = onReady
        self.onUnreadChange = onUnreadChange
        self.onClose = onClose
    }

    public func makeUIViewController(context: Context) -> TicketRackrSupportViewController {
        let getSupportLink = getSupportLink
        let controller = TicketRackrSupportViewController(getSupportLink: { try await getSupportLink() }, options: options, closable: closable)
        update(controller, context: context)
        return controller
    }

    public func updateUIViewController(_ controller: TicketRackrSupportViewController, context: Context) {
        update(controller, context: context)
    }

    private func update(_ controller: TicketRackrSupportViewController, context: Context) {
        controller.onReady = onReady
        controller.onUnreadChange = onUnreadChange
        let dismiss = context.environment.dismiss
        controller.onClose = onClose ?? { dismiss() }
    }
}

/// A Help button that opens the company's support in a sheet. Its badge counts the replies left unread when support was
/// last open.
public struct SupportButton: View {
    private let getSupportLink: GetSupportLink
    private let options: SupportOptions
    private let label: String?
    private let color: Color
    private let onOpenChange: ((Bool) -> Void)?
    @State private var open = false
    @State private var unread = 0

    /// - Parameters:
    ///   - getSupportLink: Gets a new support link from your server.
    ///   - options: What to open: a request type's form, filled in, in a language.
    ///   - label: The button's text. "Help", in the support language, when left out.
    ///   - color: The button's color: your brand color.
    public init(
        getSupportLink: @escaping GetSupportLink,
        options: SupportOptions = SupportOptions(),
        label: String? = nil,
        color: Color = Color(red: 0x16 / 255, green: 0x77 / 255, blue: 0x6B / 255),
        onOpenChange: ((Bool) -> Void)? = nil
    ) {
        self.getSupportLink = getSupportLink
        self.options = options
        self.label = label
        self.color = color
        self.onOpenChange = onOpenChange
    }

    public var body: some View {
        let words = SupportWords.forLanguage(options.language)
        let name = label ?? words.help
        Button {
            open = true
        } label: {
            HStack(spacing: 8) {
                Text(name).fontWeight(.semibold)
                if unread > 0 {
                    Text("\(unread)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.white))
                }
            }
            .foregroundColor(.white)
            .padding(.vertical, 12)
            .padding(.horizontal, 18)
            .background(Capsule().fill(color))
        }
        .accessibilityLabel(unread > 0 ? "\(name), \(unread) \(words.unread)" : name)
        .sheet(isPresented: $open) {
            TicketRackrSupportView(
                getSupportLink: getSupportLink,
                options: options,
                closable: true,
                onUnreadChange: { unread = $0 },
                onClose: { open = false }
            )
            .ignoresSafeArea()
        }
        .onChange(of: open) { onOpenChange?($0) }
    }
}
#endif
