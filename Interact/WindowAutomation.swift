import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Darwin
import ScreenCaptureKit

enum WindowAutomationError: LocalizedError {
    case noWindowSelected
    case accessibilityNotGranted
    case couldNotActivate
    case screenshotFailed
    case emptyText
    case unsupportedKey(String)

    var errorDescription: String? {
        switch self {
        case .noWindowSelected:
            return "Select a window before performing this action."
        case .accessibilityNotGranted:
            return "Grant Accessibility access to InteractApp in System Settings → Privacy & Security → Accessibility."
        case .couldNotActivate:
            return "Unable to bring the target window to the foreground."
        case .screenshotFailed:
            return "Failed to capture a screenshot for the selected window."
        case .emptyText:
            return "Provide text to send to the window."
        case .unsupportedKey(let value):
            return "The key \"\(value)\" is not recognized. Try a single character or a supported key name."
        }
    }
}

enum KeyboardModifier: String, CaseIterable, Identifiable {
    case command
    case option
    case control
    case shift

    var id: String { rawValue }

    var cgFlag: CGEventFlags {
        switch self {
        case .command: return .maskCommand
        case .option: return .maskAlternate
        case .control: return .maskControl
        case .shift: return .maskShift
        }
    }
}

final class WindowAutomation {
    static let shared = WindowAutomation()

    private init() {}

    func captureImage(of window: WindowInfo?) throws -> NSImage {
        guard let window else {
            throw WindowAutomationError.noWindowSelected
        }
        guard CGPreflightScreenCaptureAccess() else {
            throw WindowAutomationError.screenshotFailed
        }

        let cgImage = try captureImageWithScreenCaptureKit(windowID: window.id)

        let size = NSSize(width: cgImage.width, height: cgImage.height)
        return NSImage(cgImage: cgImage, size: size)
    }

    func sendText(_ text: String, to window: WindowInfo?) throws {
        guard let window else { throw WindowAutomationError.noWindowSelected }
        guard !text.isEmpty else { throw WindowAutomationError.emptyText }
        guard AXIsProcessTrusted() else { throw WindowAutomationError.accessibilityNotGranted }

        try activate(window: window)

        var unicodeScalars = Array(text.utf16)
        guard let eventSource = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: false) else {
            throw WindowAutomationError.accessibilityNotGranted
        }

        keyDown.keyboardSetUnicodeString(stringLength: unicodeScalars.count, unicodeString: &unicodeScalars)
        keyDown.postToPid(window.processID)

        keyUp.keyboardSetUnicodeString(stringLength: unicodeScalars.count, unicodeString: &unicodeScalars)
        keyUp.postToPid(window.processID)
    }

    func sendShortcut(key: String, modifiers: Set<KeyboardModifier>, to window: WindowInfo?) throws {
        guard let window else { throw WindowAutomationError.noWindowSelected }
        guard AXIsProcessTrusted() else { throw WindowAutomationError.accessibilityNotGranted }
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let keyCode = KeyCodeMapper.keyCode(for: trimmedKey) else {
            throw WindowAutomationError.unsupportedKey(trimmedKey.isEmpty ? "∅" : trimmedKey)
        }

        try activate(window: window)

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            throw WindowAutomationError.accessibilityNotGranted
        }

        let flags = modifiers.reduce(CGEventFlags()) { partialResult, modifier in
            partialResult.union(modifier.cgFlag)
        }

        keyDown.flags = flags
        keyDown.postToPid(window.processID)

        keyUp.flags = flags
        keyUp.postToPid(window.processID)
    }

    private func activate(window: WindowInfo) throws {
        guard let app = NSRunningApplication(processIdentifier: window.processID) else {
            throw WindowAutomationError.couldNotActivate
        }

        let success = app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        if !success {
            throw WindowAutomationError.couldNotActivate
        }
        usleep(120_000) // Give AppKit a moment to focus the window before sending events.
    }

    private func captureImageWithScreenCaptureKit(windowID: CGWindowID) throws -> CGImage {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<CGImage, Error>?

        Task.detached(priority: .userInitiated) {
            do {
                let content = try await SCShareableContent.current
                guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                    throw WindowAutomationError.screenshotFailed
                }

                let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                let config = SCStreamConfiguration()
                let scale = max(1.0, Double(filter.pointPixelScale))
                let frame = scWindow.frame
                let width = max(1, size_t((Double(frame.width) * scale).rounded()))
                let height = max(1, size_t((Double(frame.height) * scale).rounded()))
                config.width = width
                config.height = height

                SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, error in
                    if let image {
                        result = .success(image)
                    } else if let error {
                        result = .failure(error)
                    } else {
                        result = .failure(WindowAutomationError.screenshotFailed)
                    }
                    semaphore.signal()
                }
            } catch {
                result = .failure(error)
                semaphore.signal()
            }
        }

        let waitResult = semaphore.wait(timeout: .now() + 5)
        guard waitResult == .success, let outcome = result else {
            throw WindowAutomationError.screenshotFailed
        }

        switch outcome {
        case .success(let image):
            return image
        case .failure(let error):
            if let automationError = error as? WindowAutomationError {
                throw automationError
            } else {
                throw WindowAutomationError.screenshotFailed
            }
        }
    }
}
