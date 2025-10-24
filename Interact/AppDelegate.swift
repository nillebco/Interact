import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prompt for accessibility / screen recording on first launch.
        AuthorizationManager.shared.ensureAccessibilityPermission()
        AuthorizationManager.shared.ensureScreenRecordingPermission()
        AuthorizationManager.shared.refreshStatuses()
    }
}
