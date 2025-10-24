import Foundation
import Testing
@testable import Interact

// MARK: - Test Doubles

final class MockKeychainService: KeychainServicing {
    private(set) var storage: [String: String] = [:]

    func save(_ value: String?, for key: String) throws {
        if let value {
            storage[key] = value
        } else {
            storage.removeValue(forKey: key)
        }
    }

    func readValue(for key: String) throws -> String? {
        storage[key]
    }
}

final class TestSettingsStore: AISettingsStoring {
    private(set) var configuration: AIConfiguration

    init(initial: AIConfiguration = .default) {
        self.configuration = initial
    }

    func load() throws -> AIConfiguration {
        configuration
    }

    func save(_ configuration: AIConfiguration) throws {
        self.configuration = configuration
    }
}

struct MockOllamaClient: OllamaClientProtocol {
    var models: [AIModel] = []
    var availability: Bool = true

    func checkAvailability(host: String, port: Int) async -> Bool {
        availability
    }

    func listModels(host: String, port: Int) async throws -> [AIModel] {
        models
    }

    func generateResponse(host: String, port: Int, model: String, messages: [AIMessage]) async throws -> String {
        "response"
    }
}

struct MockOpenAIClient: OpenAIClientProtocol {
    var models: [AIModel] = []
    var availability: Bool = true

    func checkAvailability(apiKey: String?, endpoint: String) async -> Bool {
        availability
    }

    func listModels(apiKey: String, endpoint: String) async throws -> [AIModel] {
        models
    }

    func generateResponse(apiKey: String, endpoint: String, model: String, messages: [AIMessage], tools: [AITool]) async throws -> String {
        "openai"
    }
}

// MARK: - Tests

@MainActor
struct AISettingsStoreTests {
    @Test func savePersistsAPIKeyInKeychainOnly() async throws {
        let suiteName = "ai-settings-store-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create user defaults suite for testing")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        let keychain = MockKeychainService()
        let store = UserDefaultsAISettingsStore(defaults: defaults, keychain: keychain)

        var configuration = AIConfiguration.default
        configuration.provider = .openAI
        configuration.openAIApiKey = "secret-key"

        try store.save(configuration)

        #expect(defaults.data(forKey: "ai.configuration") != nil)

        // Decode stored configuration and assert the API key was stripped.
        if let data = defaults.data(forKey: "ai.configuration") {
            let decoded = try JSONDecoder().decode(AIConfiguration.self, from: data)
            #expect(decoded.openAIApiKey == nil)
        }

        // Keychain should still return the API key on load.
        let loaded = try store.load()
        #expect(loaded.openAIApiKey == "secret-key")
        #expect(loaded.prompt == AIConfiguration.defaultPrompt)
    }
}

@MainActor
struct AIServiceTests {
    @Test func listModelsUsesOllamaClient() async throws {
        let models = [AIModel(id: "model1", name: "model1", provider: .ollama)]
        let settingsStore = TestSettingsStore(initial: AIConfiguration(
            provider: .ollama,
            selectedModelID: nil,
            ollamaHost: "http://localhost",
            ollamaPort: 11434,
            openAIEndpoint: AIConfiguration.default.openAIEndpoint,
            openAIApiKey: nil,
            prompt: AIConfiguration.defaultPrompt
        ))
        let service = AIService(
            settingsStore: settingsStore,
            ollamaClient: MockOllamaClient(models: models),
            openAIClient: MockOpenAIClient()
        )

        let fetched = try await service.listModels()
        #expect(fetched == models)
    }

    @Test func listModelsThrowsWhenOpenAIKeyMissing() async throws {
        let settingsStore = TestSettingsStore(initial: AIConfiguration(
            provider: .openAI,
            selectedModelID: nil,
            ollamaHost: "http://localhost",
            ollamaPort: 11434,
            openAIEndpoint: AIConfiguration.default.openAIEndpoint,
            openAIApiKey: nil,
            prompt: AIConfiguration.defaultPrompt
        ))
        let service = AIService(
            settingsStore: settingsStore,
            ollamaClient: MockOllamaClient(),
            openAIClient: MockOpenAIClient()
        )

        await #expect(throws: AIServiceError.missingAPIKey) {
            _ = try await service.listModels()
        }
    }
}

@MainActor
struct AISettingsViewModelTests {
    @Test func saveChangesSanitizesEmptyHost() async throws {
        let initialConfig = AIConfiguration(
            provider: .ollama,
            selectedModelID: nil,
            ollamaHost: "http://localhost",
            ollamaPort: 11434,
            openAIEndpoint: AIConfiguration.default.openAIEndpoint,
            openAIApiKey: nil,
            prompt: AIConfiguration.defaultPrompt
        )
        let store = TestSettingsStore(initial: initialConfig)
        let service = AIService(
            settingsStore: store,
            ollamaClient: MockOllamaClient(),
            openAIClient: MockOpenAIClient()
        )
        let viewModel = AISettingsViewModel(service: service)
        viewModel.ollamaHost = "   "
        viewModel.ollamaPort = "11434"
        viewModel.prompt = "   "

        await viewModel.saveChanges()

        #expect(store.configuration.ollamaHost == AIConfiguration.default.ollamaHost)
        #expect(store.configuration.prompt == AIConfiguration.defaultPrompt)
        #expect(viewModel.statusMessage == "Settings saved.")
    }
}
