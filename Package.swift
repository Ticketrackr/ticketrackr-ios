// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TicketRackrSupport",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "TicketRackrSupport", targets: ["TicketRackrSupport"]),
    ],
    targets: [
        // The embedded support protocol (sdks/protocol in TicketRackr's repository): Foundation only, so it's tested on
        // any Mac against the cases every TicketRackr SDK passes.
        .target(name: "TicketRackrSupportCore"),
        // Support on screen: UIKit and SwiftUI (iOS).
        .target(name: "TicketRackrSupport", dependencies: ["TicketRackrSupportCore"]),
        .testTarget(
            name: "TicketRackrSupportCoreTests",
            dependencies: ["TicketRackrSupportCore"],
            resources: [.copy("conformance.json")]
        ),
    ]
)
