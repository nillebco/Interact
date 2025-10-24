import Foundation
import Testing
@testable import Interact

@MainActor
struct AuthorizationManagerTests {
    @Test func ensureAccessibilityPermissionRequestsPromptOptions() async throws {
        var capturedOptions: [String: Bool]?
        let expectedOptions: NSDictionary = ["MockPromptKey": true]

        let manager = AuthorizationManager(
            accessibilityStatusProvider: { false },
            screenRecordingStatusProvider: { false },
            accessibilityRequest: { options in
                if let dictionary = options as? [String: Bool] {
                    capturedOptions = dictionary
                }
                return true
            },
            screenRecordingRequest: { true },
            accessibilityPromptOptionsProvider: { expectedOptions }
        )

        manager.ensureAccessibilityPermission()

        #expect(capturedOptions?["MockPromptKey"] == true)
    }

    @Test func refreshStatusesUpdatesPublishedValues() async throws {
        var accessibilityStatus = false
        var screenRecordingStatus = false

        let manager = AuthorizationManager(
            accessibilityStatusProvider: { accessibilityStatus },
            screenRecordingStatusProvider: { screenRecordingStatus },
            accessibilityRequest: { _ in true },
            screenRecordingRequest: { true }
        )

        #expect(manager.accessibilityAuthorized == false)
        #expect(manager.screenRecordingAuthorized == false)

        accessibilityStatus = true
        screenRecordingStatus = true

        manager.refreshStatuses()

        #expect(manager.accessibilityAuthorized == true)
        #expect(manager.screenRecordingAuthorized == true)
    }

    @Test func ensureScreenRecordingPermissionRequestsAccessWhenNeeded() async throws {
        var screenRecordingStatus = false
        var requestCount = 0

        let manager = AuthorizationManager(
            accessibilityStatusProvider: { true },
            screenRecordingStatusProvider: { screenRecordingStatus },
            accessibilityRequest: { _ in true },
            screenRecordingRequest: {
                requestCount += 1
                return true
            }
        )

        manager.ensureScreenRecordingPermission()
        #expect(requestCount == 1)

        screenRecordingStatus = true
        manager.ensureScreenRecordingPermission()
        #expect(requestCount == 1)
    }
}
