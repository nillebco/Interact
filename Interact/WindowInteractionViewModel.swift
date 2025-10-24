import AppKit
import Combine

@MainActor
final class WindowInteractionViewModel: ObservableObject {
    @Published private(set) var windows: [WindowInfo] = []
    @Published var selectedWindowID: CGWindowID?
    @Published var screenshot: NSImage?
    @Published var textToSend: String = ""
    @Published var shortcutInput = ShortcutInput()
    @Published var lastError: String?
    @Published var isBusy = false

    var selectedWindow: WindowInfo? {
        guard let id = selectedWindowID else { return nil }
        return windows.first(where: { $0.id == id })
    }

    func refreshWindows() {
        windows = WindowService.fetchWindows()
        if let selectedWindowID, !windows.contains(where: { $0.id == selectedWindowID }) {
            self.selectedWindowID = windows.first?.id
        } else if selectedWindowID == nil {
            selectedWindowID = windows.first?.id
        }
    }

    func captureScreenshot() {
        do {
            lastError = nil
            screenshot = try WindowAutomation.shared.captureImage(of: selectedWindow)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func sendText() {
        do {
            lastError = nil
            try WindowAutomation.shared.sendText(textToSend, to: selectedWindow)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func sendShortcut() {
        do {
            lastError = nil
            try WindowAutomation.shared.sendShortcut(
                key: shortcutInput.key,
                modifiers: shortcutInput.modifiers,
                to: selectedWindow
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    func saveScreenshotToDesktop() {
        guard let screenshot else {
            lastError = "Capture a screenshot first."
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let namePart = selectedWindow?.displayTitle.replacingOccurrences(of: " ", with: "_") ?? "Window"
        let filename = "InteractApp_\(namePart)_\(formatter.string(from: Date())).png"

        let destinationURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)

        guard
            let tiffData = screenshot.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            lastError = "Unable to prepare PNG data for saving."
            return
        }

        do {
            try pngData.write(to: destinationURL, options: [.atomic])
        } catch {
            lastError = "Failed to save screenshot: \(error.localizedDescription)"
        }
    }

    func clearError() {
        lastError = nil
    }

    func perform(invocation: AIToolInvocation) throws -> String {
        switch invocation.name {
        case "capture_screenshot":
            captureScreenshot()
            return "Screenshot captured."
        case "type_text":
            let text = invocation.arguments["text"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let text, text.isEmpty == false else {
                throw AIServiceError.missingToolArgument("text")
            }
            textToSend = text
            sendText()
            return "Typed text in the selected window."
        case "send_shortcut":
            try sendShortcut(invocation: invocation)
            return "Shortcut sent."
        default:
            throw AIServiceError.unknownTool(invocation.name)
        }
    }

    private func sendShortcut(invocation: AIToolInvocation) throws {
        guard let keyValue = invocation.arguments["key"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              keyValue.isEmpty == false else {
            throw AIServiceError.missingToolArgument("key")
        }

        shortcutInput.key = keyValue
        shortcutInput.useCommand = invocation.arguments["command"].map(Self.isTrue) ?? false
        shortcutInput.useOption = invocation.arguments["option"].map(Self.isTrue) ?? false
        shortcutInput.useControl = invocation.arguments["control"].map(Self.isTrue) ?? false
        shortcutInput.useShift = invocation.arguments["shift"].map(Self.isTrue) ?? false

        sendShortcut()
    }

    private static func isTrue(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "true" || normalized == "1" || normalized == "yes"
    }
}
