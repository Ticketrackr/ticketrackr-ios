#if os(iOS)
import os
import TicketRackrSupportCore
import UIKit
import WebKit

/// Gets a new one-time support link from your server: the `url` from POST /v1/support-portal/links, made for the
/// signed-in customer. Called when support opens and again whenever its session ends. Your TicketRackr key stays on
/// your server.
public typealias GetSupportLink = @Sendable () async throws -> String

let log = Logger(subsystem: "com.ticketrackr.support", category: "support")

/// The company's support inside your app: requests and reports with their forms, the conversation, files, the AI
/// assistant and surveys. It fills its view. TicketRackr pages opened from it (the status page, help articles, files)
/// show in a sheet over it; other sites, mail and phone links open in their own apps.
@MainActor
public final class TicketRackrSupportViewController: UIViewController {
    /// Support has loaded and signed in.
    public var onReady: (() -> Void)?
    /// The customer's unread replies, whenever the number changes.
    public var onUnreadChange: ((Int) -> Void)?
    /// The customer pressed Close (support shows Close when `closable`). When this isn't set, support dismisses
    /// itself.
    public var onClose: (() -> Void)?

    private let getSupportLink: GetSupportLink
    private let options: SupportOptions
    private let closable: Bool
    private let words: SupportWords
    private var webView: WKWebView!
    private let status = UIStackView()
    private let message = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let retry = UIButton(type: .system)
    private var origin: String?
    private var loads = 0
    private var reconnect = ReconnectGuard()
    private var opening: Task<Void, Never>?

    /// - Parameters:
    ///   - getSupportLink: Gets a new support link from your server.
    ///   - options: What to open, in a language: a request type's form, filled in, or one of the customer's requests.
    ///   - closable: Show a Close button, for support shown in a sheet or a screen of its own.
    public init(getSupportLink: @escaping GetSupportLink, options: SupportOptions = SupportOptions(), closable: Bool = false) {
        self.getSupportLink = getSupportLink
        self.options = options
        self.closable = closable
        self.words = SupportWords.forLanguage(options.language)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Use init(getSupportLink:options:closable:).")
    }

    public override func loadView() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.websiteDataStore = .default()
        let scripts = WKUserContentController()
        // The page tells the app what happened through window.TicketRackrSupportBridge (sdks/protocol, section 3).
        scripts.addUserScript(WKUserScript(source: Self.bridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        scripts.add(MessageForwarder(self), name: "ticketrackrSupport")
        configuration.userContentController = scripts
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.backgroundColor = .systemBackground
        webView.isOpaque = false
        // The page keeps clear of the status bar and home indicator itself (edges=1).
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        let view = UIView()
        view.backgroundColor = .systemBackground
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        message.numberOfLines = 0
        message.textAlignment = .center
        message.font = .preferredFont(forTextStyle: .body)
        message.textColor = .secondaryLabel
        message.adjustsFontForContentSizeCategory = true
        retry.setTitle(words.retry, for: .normal)
        retry.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        retry.addAction(UIAction { [weak self] _ in self?.tryAgain() }, for: .primaryActionTriggered)
        status.axis = .vertical
        status.alignment = .center
        status.spacing = 12
        status.addArrangedSubview(spinner)
        status.addArrangedSubview(message)
        status.addArrangedSubview(retry)
        status.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(status)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            status.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            status.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])
        self.view = view
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        open()
    }

    /// Gets a new link and shows it.
    private func open() {
        show(loading: true)
        opening?.cancel()
        opening = Task { [weak self, getSupportLink] in
            do {
                let link = try await getSupportLink()
                guard let self, !Task.isCancelled else { return }
                self.loads += 1
                let url = try SupportAddress.frameURL(link: link, options: self.options, closable: self.closable, edges: true, load: self.loads)
                self.origin = SupportOrigin.of(url.absoluteString)
                self.webView.load(URLRequest(url: url))
            } catch {
                guard let self, !Task.isCancelled else { return }
                log.error("Support couldn't open: \(error.localizedDescription, privacy: .public)")
                self.show(loading: false, failed: true)
            }
        }
    }

    private func tryAgain() {
        reconnect = ReconnectGuard()
        open()
    }

    private func show(loading: Bool, failed: Bool = false) {
        status.isHidden = !loading && !failed
        webView.isHidden = failed
        spinner.isHidden = !loading
        if loading { spinner.startAnimating() } else { spinner.stopAnimating() }
        message.text = failed ? words.failed : words.loading
        message.isHidden = !loading && !failed
        retry.isHidden = !failed
    }

    fileprivate func received(_ body: Any, from frame: WKFrameInfo) {
        // Only the support page this view shows.
        let source = frame.securityOrigin
        let sender = source.port == 0 ? "\(source.protocol)://\(source.host)" : "\(source.protocol)://\(source.host):\(source.port)"
        guard let origin, SupportOrigin.isSupport(sender, origin: origin), let data = body as? String, let event = SupportEvent.read(data) else { return }
        switch event {
        case .ready:
            show(loading: false)
            onReady?()
        case .unread(let count):
            UnreadStore.shared.report(count: count, origin: origin)
            onUnreadChange?(count)
        case .unreadToken(let token, let expiresAt):
            // For the Help button's badge while support is closed (sdks/protocol, section 7).
            UnreadStore.shared.keep(token: token, expiresAt: expiresAt, origin: origin)
        case .close:
            if let onClose { onClose() } else { presentingViewController?.dismiss(animated: true) }
        case .sessionEnded:
            if reconnect.allow() { open() } else { show(loading: false, failed: true) }
        }
    }

    /// Opens a TicketRackr page or file in a sheet over support, so support stays as it was.
    private func showPage(_ url: URL) {
        guard let origin else { return }
        let page = SupportPageViewController(url: url, origin: origin, words: words)
        present(UINavigationController(rootViewController: page), animated: true)
    }

    private func route(_ url: URL) {
        guard let origin else { return }
        switch SupportDestination.of(url.absoluteString, origin: origin) {
        case .support: break
        case .file, .page: showPage(url)
        case .outside: UIApplication.shared.open(url)
        }
    }

    // Defines window.TicketRackrSupportBridge in front of WebKit's message handler.
    private static let bridge = """
    window.TicketRackrSupportBridge = { postMessage: function (data) { window.webkit.messageHandlers.ticketrackrSupport.postMessage(String(data)); } };
    """
}

extension TicketRackrSupportViewController: WKNavigationDelegate, WKUIDelegate {
    public func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url, let origin else { return decisionHandler(.allow) }
        // Frames inside the page load as they are.
        if action.targetFrame?.isMainFrame == false || url.absoluteString == "about:blank" { return decisionHandler(.allow) }
        if action.targetFrame != nil, SupportDestination.of(url.absoluteString, origin: origin) == .support { return decisionHandler(.allow) }
        decisionHandler(.cancel)
        route(url)
    }

    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // A new window (window.open): it goes where any other link would.
        if let url = action.request.url { route(url) }
        return nil
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        show(loading: false)
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failed(error)
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failed(error)
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // iOS ended the page to save memory: open it again.
        open()
    }

    private func failed(_ error: Error) {
        let error = error as NSError
        // A navigation replaced by another, or one this view cancelled: not a failure.
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled { return }
        if error.domain == "WebKitErrorDomain" && (error.code == 101 || error.code == 102) { return }
        log.error("Support couldn't load: \(error.localizedDescription, privacy: .public)")
        show(loading: false, failed: true)
    }
}

/// Forwards the page's messages without the content controller keeping support alive.
private final class MessageForwarder: NSObject, WKScriptMessageHandler {
    private weak var target: TicketRackrSupportViewController?

    init(_ target: TicketRackrSupportViewController) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body
        let frame = message.frameInfo
        MainActor.assumeIsolated { target?.received(body, from: frame) }
    }
}
#endif
