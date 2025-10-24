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
    @Published var userInstructions: String = ""
    @Published private(set) var chatEntries: [AIChatEntry] = []
    @Published private(set) var isAutomating = false

    var selectedWindow: WindowInfo? {
        guard let id = selectedWindowID else { return nil }
        return windows.first(where: { $0.id == id })
    }

    private let aiService: AIService
    private var conversationMessages: [AIMessage] = []
    private var lastToolInvocations: [AIToolInvocation] = []

    struct ToolExecutionResult {
        let message: String
        let imageDataURL: String?
    }

    init(aiService: AIService) {
        self.aiService = aiService
    }

    var availableTools: [AITool] {
        aiService.availableTools()
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

    func startAutomation() {
        clearError()

        guard selectedWindow != nil else {
            lastError = "Select a window before interacting with the assistant."
            return
        }

        let trimmed = userInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            lastError = "Enter instructions for the assistant first."
            return
        }

        if isAutomating {
            return
        }

        chatEntries = []
        conversationMessages = []
        appendChatEntry(author: "User", content: trimmed)
        conversationMessages.append(AIMessage(role: .user, content: trimmed))

        isAutomating = true
        lastToolInvocations = []
        Task {
            await runAutomationSession()
        }
    }

    func resetConversation() {
        chatEntries = []
        conversationMessages = []
        userInstructions = ""
        lastToolInvocations = []
        clearError()
    }

    private func runAutomationSession() async {
        defer { isAutomating = false }

        do {
            while true {
                let response = try await aiService.generateResponse(messages: conversationMessages)

                if let assistantText = response.text,
                   assistantText.isEmpty == false {
                    appendChatEntry(author: "Assistant", content: assistantText)
                    conversationMessages.append(
                        AIMessage(role: .assistant, content: assistantText)
                    )
                }

                var toolInvocations = response.toolInvocations
                if toolInvocations.isEmpty,
                   let assistantText = response.text,
                   let fallbackInvocation = parseToolInvocation(from: assistantText) {
                    toolInvocations = [fallbackInvocation]
                }

                if toolInvocations.isEmpty {
                    break
                }

                if toolInvocations == lastToolInvocations {
                    appendChatEntry(author: "System", content: "Repeated tool request detected, stopping automation.")
                    break
                }

                var requiresFollowUp = false

                for invocation in toolInvocations {
                    let result = try perform(invocation: invocation)
                    appendChatEntry(author: "Tool", content: "\(invocation.name) → \(result.message)")

                    if aiService.toolDefinition(named: invocation.name)?.requiresFollowUp == true {
                        var components: [AIMessage.Component] = [
                            .text("Tool \(invocation.name) output:\n\(result.message)")
                        ]
                        if let imageDataURL = result.imageDataURL {
                            components.append(.imageDataURL(imageDataURL))
                        }
                        conversationMessages.append(
                            AIMessage(role: .user, components: components)
                        )
                        requiresFollowUp = true
                    }
                }

                lastToolInvocations = toolInvocations

                if requiresFollowUp == false {
                    break
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func perform(invocation: AIToolInvocation) throws -> ToolExecutionResult {
        switch invocation.name {
        case "capture_screenshot":
            captureScreenshot()
            guard let artifacts = try saveScreenshotForTool() else {
                return ToolExecutionResult(
                    message: "Screenshot captured, but saving failed.",
                    imageDataURL: nil
                )
            }
            let description = "Screenshot saved to \(artifacts.path). Automated visual analysis is not available, please review the image manually."
            return ToolExecutionResult(message: description, imageDataURL: artifacts.dataURL)
        case "type_text":
            let text = invocation.arguments["text"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let text, text.isEmpty == false else {
                throw AIServiceError.missingToolArgument("text")
            }
            textToSend = text
            sendText()
            return ToolExecutionResult(message: "Typed text in the selected window.", imageDataURL: nil)
        case "send_shortcut":
            try sendShortcut(invocation: invocation)
            return ToolExecutionResult(message: "Shortcut sent.", imageDataURL: nil)
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

    private func saveScreenshotForTool() throws -> (path: String, dataURL: String)? {
        guard let screenshot else {
            return nil
        }

        guard
            let tiffData = screenshot.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            return nil
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("InteractScreenshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let filename = "InteractScreenshot_\(UUID().uuidString).png"
        let destination = directory.appendingPathComponent(filename)
        try pngData.write(to: destination, options: .atomic)

        let base64 = pngData.base64EncodedString()
        let dataURL = "data:image/png;base64,\(base64)"
        return (destination.path, dataURL)
    }

    private func appendChatEntry(author: String, content: String) {
        chatEntries.append(AIChatEntry(author: author, content: content))
    }

    private func parseToolInvocation(from content: String) -> AIToolInvocation? {
        guard let jsonString = extractJSONPayload(from: content)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let data = jsonString.data(using: .utf8)
        else {
            return nil
        }

        return try? JSONDecoder().decode(AIToolInvocation.self, from: data)
    }

    private func extractJSONPayload(from content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("```") {
            // Extract content inside code fences
            var stripped = trimmed
            stripped.removeFirst(3)
            if let range = stripped.range(of: "```", options: [], range: stripped.startIndex..<stripped.endIndex, locale: nil) {
                let payload = stripped[stripped.startIndex..<range.lowerBound]
                return payload.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}")
        else { return nil }

        let jsonSubstring = trimmed[start...end]
        return String(jsonSubstring)
    }
}

struct AIChatEntry: Identifiable {
    let id = UUID()
    let author: String
    let content: String
}
