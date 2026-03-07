import SwiftUI

// MARK: - App Entry Point

@available(macOS 13.0, *)
@main
struct MeetingRecorderApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No windows — this is a menu bar only app.
        // The NSStatusItem and popover are managed by AppDelegate.
        Settings {
            EmptyView()
        }
    }
}
