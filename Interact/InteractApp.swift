import SwiftUI
import AppKit

@main
struct InteractAppApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var authManager = AuthorizationManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowStyle(.automatic)
    }
}
