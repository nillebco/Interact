import Foundation

enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case ollama
    case openAI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama:
            return "Ollama"
        case .openAI:
            return "OpenAI"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .ollama:
            return false
        case .openAI:
            return true
        }
    }
}
