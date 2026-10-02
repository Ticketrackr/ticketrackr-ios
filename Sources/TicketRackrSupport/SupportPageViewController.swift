#if os(iOS)
import TicketRackrSupportCore
import UIKit
import WebKit

/// A TicketRackr page or file opened from support (the status page, a help article, an attachment), in a sheet with a
/// Back button. It shares support's sign-in, so a file loads without signing in again.
@MainActor
final class SupportPageViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private let url: URL
    private let origin: String
    private let words: SupportWords
    private var webView: WKWebView!

    init(url: URL, origin: String, words: SupportWords) {
        self.url = url
        self.origin = origin
        self.words = words
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Not used.")
    }

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.backgroundColor = .systemBackground
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        var back = UIButton.Configuration.plain()
        back.image = UIImage(systemName: "chevron.backward")
        back.title = words.back
        back.imagePadding = 4
        let button = UIButton(configuration: back, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: button)
        webView.load(URLRequest(url: url))
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.allow) }
        if action.targetFrame?.isMainFrame == false || url.absoluteString == "about:blank" { return decisionHandler(.allow) }
        switch SupportDestination.of(url.absoluteString, origin: origin) {
        case .page, .file:
            if action.targetFrame == nil {
                // A new window: show it here instead.
                decisionHandler(.cancel)
                webView.load(URLRequest(url: url))
            } else {
                decisionHandler(.allow)
            }
        case .support:
            // A link back to support: support is right underneath.
            decisionHandler(.cancel)
            dismiss(animated: true)
        case .outside:
            decisionHandler(.cancel)
            UIApplication.shared.open(url)
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // A new window (window.open): TicketRackr pages show here, the rest where they belong.
        guard let url = action.request.url else { return nil }
        switch SupportDestination.of(url.absoluteString, origin: origin) {
        case .page, .file: webView.load(URLRequest(url: url))
        case .support: dismiss(animated: true)
        case .outside: UIApplication.shared.open(url)
        }
        return nil
    }
}
#endif
