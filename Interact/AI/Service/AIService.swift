import Foundation

struct AITestResult: Equatable {
    let success: Bool
    let message: String
}

struct AIResponse {
    let text: String?
    let toolInvocations: [AIToolInvocation]
}

enum AIServiceError: Error, LocalizedError {
    case missingAPIKey
    case missingModelSelection
    case missingToolArgument(String)
    case unknownTool(String)
    case unreachableEndpoint(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "An API key is required for the selected provider."
        case .missingModelSelection:
            return "Select a model before requesting a response."
        case .missingToolArgument(let name):
            return "Missing required argument: \(name)."
        case .unknownTool(let name):
            return "Unknown tool: \(name)."
        case .unreachableEndpoint(let target):
            return "Unable to contact \(target). Verify the address and your network connection."
        }
    }
}

@MainActor
final class AIService {
    private let settingsStore: AISettingsStoring
    private let ollamaClient: OllamaClientProtocol
    private let openAIClient: OpenAIClientProtocol
    private var configurationCache: AIConfiguration?

    static let tools: [AITool] = [
        AITool(
            name: "capture_screenshot",
            summary: "Capture a screenshot of the currently selected window.",
            requiresFollowUp: true,
            parameters: []
        ),
        AITool(
            name: "type_text",
            summary: "Type arbitrary text into the selected window.",
            parameters: [
                .init(name: "text", type: .string, description: "The text to type into the window.", required: true)
            ]
        ),
        AITool(
            name: "send_shortcut",
            summary: "Send a keyboard shortcut to the selected window (e.g. command+c).",
            parameters: [
                .init(name: "key", type: .string, description: "The key to press (for example: c, enter, escape).", required: true),
                .init(name: "command", type: .boolean, description: "Include the Command modifier.", required: false),
                .init(name: "option", type: .boolean, description: "Include the Option modifier.", required: false),
                .init(name: "control", type: .boolean, description: "Include the Control modifier.", required: false),
                .init(name: "shift", type: .boolean, description: "Include the Shift modifier.", required: false)
            ]
        )
    ]

    init(
        settingsStore: AISettingsStoring = UserDefaultsAISettingsStore(),
        ollamaClient: OllamaClientProtocol = OllamaClient(),
        openAIClient: OpenAIClientProtocol = OpenAIClient()
    ) {
        self.settingsStore = settingsStore
        self.ollamaClient = ollamaClient
        self.openAIClient = openAIClient
    }

    func loadConfiguration() throws -> AIConfiguration {
        if let configurationCache {
            return configurationCache
        }
        let configuration = try settingsStore.load()
        configurationCache = configuration
        return configuration
    }

    func updateConfiguration(_ configuration: AIConfiguration) throws {
        try settingsStore.save(configuration)
        configurationCache = configuration
    }

    func availableTools() -> [AITool] {
        Self.tools
    }

    func toolDefinition(named name: String) -> AITool? {
        Self.tools.first(where: { $0.name == name })
    }

    func listModels(for provider: AIProvider? = nil) async throws -> [AIModel] {
        let configuration = try loadConfiguration()
        let providerToUse = provider ?? configuration.provider

        switch providerToUse {
        case .ollama:
            do {
                return try await ollamaClient.listModels(
                    host: configuration.ollamaHost,
                    port: configuration.ollamaPort
                )
            } catch {
                throw mapNetworkError(
                    error,
                    description: "Ollama at \(configuration.ollamaHost):\(configuration.ollamaPort)"
                )
            }
        case .openAI:
            guard let apiKey = configuration.openAIApiKey, apiKey.isEmpty == false else {
                throw AIServiceError.missingAPIKey
            }
            do {
                return try await openAIClient.listModels(
                    apiKey: apiKey,
                    endpoint: configuration.openAIEndpoint
                )
            } catch {
                throw mapNetworkError(error, description: configuration.openAIEndpoint)
            }
        }
    }

    func testConnection(for provider: AIProvider? = nil) async -> AITestResult {
        let configuration = (try? loadConfiguration()) ?? .default
        let providerToTest = provider ?? configuration.provider

        switch providerToTest {
        case .ollama:
            let reachable = await ollamaClient.checkAvailability(
                host: configuration.ollamaHost,
                port: configuration.ollamaPort
            )
            let message = reachable
                ? "Ollama is reachable at \(configuration.ollamaHost):\(configuration.ollamaPort)."
                : "Unable to reach Ollama at \(configuration.ollamaHost):\(configuration.ollamaPort)."
            return AITestResult(success: reachable, message: message)
        case .openAI:
            guard let apiKey = configuration.openAIApiKey, apiKey.isEmpty == false else {
                return AITestResult(success: false, message: "Provide an OpenAI API key.")
            }
            let reachable = await openAIClient.checkAvailability(
                apiKey: apiKey,
                endpoint: configuration.openAIEndpoint
            )
            let message = reachable
                ? "OpenAI credentials are valid."
                : "OpenAI validation failed. Check your API key and endpoint."
            return AITestResult(success: reachable, message: message)
        }
    }

    func generateResponse(
        messages: [AIMessage],
        overrideModelID: String? = nil
    ) async throws -> AIResponse {
        let configuration = try loadConfiguration()
        switch configuration.provider {
        case .ollama:
            guard let modelID = overrideModelID ?? configuration.selectedModelID else {
                throw AIServiceError.missingModelSelection
            }
            var payloadMessages = messages
            payloadMessages.insert(toolingMessage(using: configuration), at: 0)
            let text = try await ollamaClient.generateResponse(
                host: configuration.ollamaHost,
                port: configuration.ollamaPort,
                model: modelID,
                messages: payloadMessages
            )
            return AIResponse(text: text, toolInvocations: [])
        case .openAI:
            guard let apiKey = configuration.openAIApiKey, apiKey.isEmpty == false else {
                throw AIServiceError.missingAPIKey
            }
            guard let modelID = overrideModelID ?? configuration.selectedModelID else {
                throw AIServiceError.missingModelSelection
            }
            var payloadMessages = messages
            payloadMessages.insert(toolingMessage(using: configuration), at: 0)
            do {
                return try await openAIClient.generateResponse(
                    apiKey: apiKey,
                    endpoint: configuration.openAIEndpoint,
                    model: modelID,
                    messages: payloadMessages,
                    tools: Self.tools
                )
            } catch {
                throw mapNetworkError(error, description: configuration.openAIEndpoint)
            }
        }
    }

    private func toolingMessage(using configuration: AIConfiguration) -> AIMessage {
        let toolList = Self.tools.map { tool in
            let parameterList = tool.parameters.map { parameter in
                "- \(parameter.name) (\(parameter.type.rawValue))\(parameter.required ? " [required]" : ""): \(parameter.description)"
            }
            let joinedParameters = parameterList.joined(separator: "\n")
            let parameterSection = joinedParameters.isEmpty ? "- No parameters." : joinedParameters
            return "• \(tool.name): \(tool.summary)\n\(parameterSection)"
        }.joined(separator: "\n\n")

        let instructions = """
\(configuration.prompt)

Available tools:
\(toolList)

When you need to operate the app, reply with JSON in the form:
```
{"tool": "<tool_name>", "arguments": {"key": "value"}}
```
Wrap the JSON in a Markdown code block exactly as shown so it can be parsed reliably.
Otherwise, answer with natural language guidance.
"""

        return AIMessage(role: .system, content: instructions)
    }

    private func mapNetworkError(_ error: Error, description: String) -> Error {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotFindHost, .notConnectedToInternet, .networkConnectionLost, .dnsLookupFailed, .timedOut:
                return AIServiceError.unreachableEndpoint(description)
            default:
                break
            }
        }
        return error
    }

}
