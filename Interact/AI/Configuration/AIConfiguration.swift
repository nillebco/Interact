import Foundation

struct AIConfiguration: Equatable, Codable {
    var provider: AIProvider
    var selectedModelID: String?
    var ollamaHost: String
    var ollamaPort: Int
    var openAIEndpoint: String
    var openAIApiKey: String?
    var prompt: String

    static let `default` = AIConfiguration(
        provider: .ollama,
        selectedModelID: nil,
        ollamaHost: "http://localhost",
        ollamaPort: 11434,
        openAIEndpoint: "https://api.openai.com/v1",
        openAIApiKey: nil,
        prompt: Self.defaultPrompt
    )

    static let defaultPrompt = "You are a helpful assistant. You can capture screenshots and type text or send shortcuts into the selected app. Use the available tools to perform the actions requested by the user within the chosen application."
}
