import Foundation
import ApplicationServices
import Combine

private let accessibilityPromptOptionsDefault: () -> CFDictionary = {
    [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: true] as CFDictionary
}

@MainActor
final class AuthorizationManager: ObservableObject {
    static let shared = AuthorizationManager()

    @Published private(set) var accessibilityAuthorized: Bool
    @Published private(set) var screenRecordingAuthorized: Bool

    private let accessibilityStatusProvider: () -> Bool
    private let screenRecordingStatusProvider: () -> Bool
    private let accessibilityRequest: (CFDictionary?) -> Bool
    private let screenRecordingRequest: () -> Bool
    private let accessibilityPromptOptionsProvider: () -> CFDictionary

    init(
        accessibilityStatusProvider: @escaping () -> Bool = { AXIsProcessTrusted() },
        screenRecordingStatusProvider: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
        accessibilityRequest: @escaping (CFDictionary?) -> Bool = { options in
            AXIsProcessTrustedWithOptions(options)
        },
        screenRecordingRequest: @escaping () -> Bool = { CGRequestScreenCaptureAccess() },
        accessibilityPromptOptionsProvider: @escaping () -> CFDictionary = accessibilityPromptOptionsDefault
    ) {
        self.accessibilityStatusProvider = accessibilityStatusProvider
        self.screenRecordingStatusProvider = screenRecordingStatusProvider
        self.accessibilityRequest = accessibilityRequest
        self.screenRecordingRequest = screenRecordingRequest
        self.accessibilityPromptOptionsProvider = accessibilityPromptOptionsProvider
        self.accessibilityAuthorized = accessibilityStatusProvider()
        self.screenRecordingAuthorized = screenRecordingStatusProvider()
    }

    func ensureAccessibilityPermission() {
        _ = accessibilityRequest(accessibilityPromptOptionsProvider())
    }

    func ensureScreenRecordingPermission() {
        guard !screenRecordingStatusProvider() else { return }
        _ = screenRecordingRequest()
    }

    func refreshStatuses() {
        accessibilityAuthorized = accessibilityStatusProvider()
        screenRecordingAuthorized = screenRecordingStatusProvider()
    }
}
