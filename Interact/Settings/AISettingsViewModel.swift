import Combine
import Foundation

@MainActor
final class AISettingsViewModel: ObservableObject {
    @Published var provider: AIProvider = .ollama
    @Published var availableModels: [AIModel] = []
    @Published var selectedModelID: String?
    @Published var ollamaHost: String = AIConfiguration.default.ollamaHost
    @Published var ollamaPort: String = String(AIConfiguration.default.ollamaPort)
    @Published var openAIEndpoint: String = AIConfiguration.default.openAIEndpoint
    @Published var openAIApiKey: String = ""
    @Published var prompt: String = AIConfiguration.defaultPrompt
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoadingModels = false
    @Published private(set) var isTestingConnection = false

    private let service: AIService

    init(service: AIService) {
        self.service = service
        load()
    }

    func load() {
        do {
            let configuration = try service.loadConfiguration()
            apply(configuration: configuration)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateProvider(_ provider: AIProvider) {
        self.provider = provider
        statusMessage = nil
    }

    func saveChanges() async {
        errorMessage = nil
        statusMessage = nil

        do {
            let configuration = try makeConfiguration()
            try service.updateConfiguration(configuration)
            apply(configuration: configuration)
            try await refreshModels()
            statusMessage = "Settings saved."
        } catch {
            errorMessage = displayableMessage(for: error)
        }
    }

    func refreshModels() async throws {
        isLoadingModels = true
        defer { isLoadingModels = false }

        do {
            let models = try await service.listModels(for: provider)
            availableModels = models
            syncSelectedModel(with: models)
        } catch {
            availableModels = []
            throw error
        }
    }

    func handleRefreshTapped() async {
        errorMessage = nil
        statusMessage = nil

        do {
            try await refreshModels()
            if availableModels.isEmpty {
                statusMessage = "No models reported by \(provider.displayName)."
            }
        } catch {
            errorMessage = displayableMessage(for: error)
        }
    }

    func selectModel(_ modelID: String?) {
        selectedModelID = modelID
    }

    func testConnection() async {
        isTestingConnection = true
        errorMessage = nil
        statusMessage = nil
        defer { isTestingConnection = false }

        let result = await service.testConnection(for: provider)
        if result.success {
            statusMessage = result.message
        } else {
            errorMessage = result.message
        }
    }

    private func apply(configuration: AIConfiguration) {
        provider = configuration.provider
        selectedModelID = configuration.selectedModelID
        ollamaHost = configuration.ollamaHost
        ollamaPort = String(configuration.ollamaPort)
        openAIEndpoint = configuration.openAIEndpoint
        openAIApiKey = configuration.openAIApiKey ?? ""
        prompt = configuration.prompt
    }

    private func makeConfiguration() throws -> AIConfiguration {
        guard let resolvedPort = Int(ollamaPort.trimmingCharacters(in: .whitespaces)), resolvedPort > 0 else {
            throw ValidationError.invalidPort
        }

        var configuration = try service.loadConfiguration()
        configuration.provider = provider
        configuration.selectedModelID = selectedModelID
        configuration.ollamaHost = sanitizeHost(ollamaHost)
        configuration.ollamaPort = resolvedPort
        configuration.openAIEndpoint = sanitizeEndpoint(openAIEndpoint)
        configuration.openAIApiKey = openAIApiKey.isEmpty ? nil : openAIApiKey
        configuration.prompt = sanitizePrompt(prompt)
        return configuration
    }

    private func syncSelectedModel(with models: [AIModel]) {
        guard let selectedModelID else { return }
        if models.contains(where: { $0.id == selectedModelID }) {
            return
        }
        self.selectedModelID = models.first?.id
    }

    private func sanitizeHost(_ host: String) -> String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AIConfiguration.default.ollamaHost : trimmed
    }

    private func sanitizeEndpoint(_ endpoint: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AIConfiguration.default.openAIEndpoint : trimmed
    }

    private func sanitizePrompt(_ prompt: String) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AIConfiguration.defaultPrompt : trimmed
    }

    private func displayableMessage(for error: Error) -> String {
        if let serviceError = error as? AIServiceError {
            return serviceError.localizedDescription
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotFindHost, .notConnectedToInternet, .networkConnectionLost, .dnsLookupFailed, .timedOut:
                return "Network connection appears offline. Check your internet connection and try again."
            default:
                break
            }
        }
        return error.localizedDescription
    }
}

extension AISettingsViewModel {
    enum ValidationError: Error, LocalizedError {
        case invalidPort

        var errorDescription: String? {
            switch self {
            case .invalidPort:
                return "Provide a valid port number for Ollama."
            }
        }
    }
}
