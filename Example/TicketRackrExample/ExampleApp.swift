import SwiftUI
import TicketRackrSupport

@main
struct ExampleApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

/// Your server's endpoint that makes a support link for the signed-in customer and returns `{"url": …}`
/// (see the README). The UI tests point it at TicketRackr running on this Mac.
private let supportLinkEndpoint = URL(string: ProcessInfo.processInfo.environment["SUPPORT_LINK_URL"] ?? "https://your-server.example.com/support-link")!

@Sendable func getSupportLink() async throws -> String {
    var request = URLRequest(url: supportLinkEndpoint)
    request.httpMethod = "POST"
    let (data, _) = try await URLSession.shared.data(for: request)
    struct Link: Decodable { let url: String }
    return try JSONDecoder().decode(Link.self, from: data).url
}

struct ContentView: View {
    @State private var screen = false
    @State private var log: [String] = []

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // A Help button that opens support in a sheet.
                SupportButton(getSupportLink: getSupportLink, color: Color(red: 0.88, green: 0.11, blue: 0.28)) { open in
                    log.append(open ? "sheet opened" : "sheet closed")
                }
                // Or support as a screen of its own.
                Button("Support as a screen") { screen = true }
                Text(log.suffix(4).joined(separator: " | "))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("log")
            }
            .navigationTitle("Example")
            .fullScreenCover(isPresented: $screen) {
                TicketRackrSupportView(
                    getSupportLink: getSupportLink,
                    closable: true,
                    onReady: { log.append("ready") },
                    onUnreadChange: { log.append("unread \($0)") },
                    onClose: { screen = false }
                )
                .ignoresSafeArea()
            }
        }
        .navigationViewStyle(.stack)
    }
}
