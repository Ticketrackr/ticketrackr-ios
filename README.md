# TicketRackr Support for iOS

Your company's TicketRackr support inside your iPhone or iPad app, without sending customers to a browser: requests
and reports with their forms, the conversation, file uploads, the AI assistant and satisfaction surveys. UIKit and
SwiftUI, iOS 15 or later.

## Install

In Xcode: **File → Add Package Dependencies…**, enter `https://github.com/Ticketrackr/ticketrackr-ios`, and add
**TicketRackrSupport** to your app. Or in `Package.swift`:

```swift
.package(url: "https://github.com/Ticketrackr/ticketrackr-ios", from: "0.3.0")
```

Customers can attach photos and videos. If your app doesn't already say why it uses the camera, photos and microphone,
add these to its Info.plist (without them, iOS closes the app when a customer chooses Take Photo):

```xml
<key>NSCameraUsageDescription</key>
<string>Take a photo to send to support.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Choose a photo to send to support.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Record a video to send to support.</string>
```

## 1. Your server makes a support link

Your TicketRackr key stays on your server, never in the app. Add an endpoint that, for the signed-in customer:

1. calls `POST https://api.ticketrackr.com/v1/customer-sessions` with `Authorization: Bearer <your key>` and
   `{"externalCustomerId": "<your id for them>", "email": "…", "name": "…"}`, which returns a `token`;
2. calls `POST https://api.ticketrackr.com/v1/support-portal/links` with `Authorization: Bearer <that token>` and `{}`;
3. returns that link's `{"url": "…"}` to the app.

Your key is one from TicketRackr (Settings → Companies → Connect) as `clientId.clientSecret`. A sandbox key shows the
sandbox's test data; a live key, your real customers'. Use your database's id for the customer, not something that
changes like an email address.

Send the customer's email whenever you have it: support emails them there when it replies, and it's how they get
back to their requests. Without one, support asks the customer for an email and confirms it with a code before they
can start a request.

## 2. Show support

Give support a way to get a link from your endpoint:

```swift
import TicketRackrSupport

@Sendable func getSupportLink() async throws -> String {
    var request = URLRequest(url: URL(string: "https://your-api.example.com/support-link")!)
    request.httpMethod = "POST"
    request.setValue("Bearer \(yourSessionToken)", forHTTPHeaderField: "Authorization")
    let (data, _) = try await URLSession.shared.data(for: request)
    struct Link: Decodable { let url: String }
    return try JSONDecoder().decode(Link.self, from: data).url
}
```

**SwiftUI.** A Help button that opens support in a sheet, with a badge for unread replies:

```swift
SupportButton(getSupportLink: getSupportLink, color: .pink)
```

Or support as a screen of your own, filling it:

```swift
TicketRackrSupportView(getSupportLink: getSupportLink, closable: true, onClose: { showSupport = false })
    .ignoresSafeArea()
```

**UIKit.** Support in a sheet over any view controller:

```swift
TicketRackr.presentSupport(from: self, getSupportLink: getSupportLink)
```

Or `TicketRackrSupportViewController(getSupportLink:options:closable:)` wherever you show view controllers.

## Options

| | |
| --- | --- |
| `getSupportLink` | Required. Calls your endpoint and returns the link's `url`. Called on open, and again if the session ends. |
| `options: SupportOptions(requestType:)` | Open the form for one request type, by its key, such as a report: `"report_problem"`. |
| `options: SupportOptions(subject:fields:)` | Fill in the request's subject and its type's fields (by key). |
| `options: SupportOptions(ticket:)` | Open one of the customer's requests, by its id: `ticket.id` from the `ticket.message.created` webhook, for example when the customer taps a notification about a reply. Another customer's request isn't opened; support shows their own requests instead. |
| `options: SupportOptions(language:)` | `en`, `es`, `fr`, `de` or `pt`. The device's language when left out. |
| `onReady`, `onUnreadChange`, `onClose` | Support has loaded; the customer's unread replies, whenever the number changes; the customer pressed Close. |
| `closable` | Show a Close button: for support in a sheet or a screen of its own. |
| `label`, `color`, `onOpenChange` | `SupportButton` only: its text (default "Help"), color, and the sheet opening or closing. |

## Unread replies

`SupportButton`'s badge counts the customer's unread replies, even while support is closed: an agent who answers while
the customer is elsewhere in your app shows on the button when it next appears, or when your app comes back to the
foreground. It works by itself, with no code of yours and no support session (sessions count toward your plan). Each
time support opens, it gives the app a token that reads that count and nothing else, for 30 days, and the button asks
with it at most once a minute.

For a badge of your own, like a tab's, ask for the count when it shows. It's nil until support has opened on the
device:

```swift
// UIKit
Task {
    let count = await TicketRackr.unreadCount() ?? 0
    tabBarItem.badgeValue = count > 0 ? String(count) : nil
}

// SwiftUI (a badge of 0 shows nothing)
.task { unread = await TicketRackr.unreadCount() ?? 0 }
.badge(unread)
```

It asks TicketRackr each time, so call it when the badge shows, not on a timer.

When your app's user signs out, call `TicketRackr.signOut()`, so the next person on the device doesn't see their
count. Badges then show nothing until support opens again.

## Request types and reports

What customers can ask for (a problem report, a billing question, reporting a user) is set in TicketRackr, not in
your code: make case types with their forms in Settings → Companies → Case types, and choose which customers see in
Settings → Companies → Support page. They appear in your app right away, with no new build.

## Good to know

- Sessions renew themselves: when one ends, support asks your endpoint for a new link.
- A file the customer opens (a photo, a PDF, a video) shows in a sheet over support, and so do TicketRackr pages like
  the status page or a help article, with a Back button, so the conversation stays where it was. Other websites, email
  and phone links open in their own apps.
- Support uses your brand color and logo from Settings → Companies → Support page.
- `Example/` is an app that shows both ways in, with UI tests. Generate its Xcode project with
  `brew install xcodegen && xcodegen` in that folder.
- Full guide and the API: https://ticketrackr.com/docs/support-api#embedded-support

## License

MIT: use it freely. It shows your support from TicketRackr, so it needs a TicketRackr account (sign up at
https://ticketrackr.com/signup).
