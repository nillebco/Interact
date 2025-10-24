import Foundation

protocol AISettingsStoring {
    func load() throws -> AIConfiguration
    func save(_ configuration: AIConfiguration) throws
}

struct UserDefaultsAISettingsStore: AISettingsStoring {
    private enum Constants {
        static let configurationKey = "ai.configuration"
        static let openAIApiKey = "ai.configuration.openai.apiKey"
    }

    private let defaults: UserDefaults
    private let keychain: KeychainServicing
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard, keychain: KeychainServicing = KeychainService()) {
        self.defaults = defaults
        self.keychain = keychain
    }

    func load() throws -> AIConfiguration {
        guard let data = defaults.data(forKey: Constants.configurationKey) else {
            return try configurationWithKeychainFallback(.default)
        }

        do {
            var storedConfiguration = try decoder.decode(AIConfiguration.self, from: data)
            if storedConfiguration.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                storedConfiguration.prompt = AIConfiguration.defaultPrompt
            }
            return try configurationWithKeychainFallback(storedConfiguration)
        } catch {
            defaults.removeObject(forKey: Constants.configurationKey)
            return try configurationWithKeychainFallback(.default)
        }
    }

    func save(_ configuration: AIConfiguration) throws {
        try storeConfigurationWithoutSecrets(configuration)
        try storeAPIKey(configuration.openAIApiKey)
    }

    private func configurationWithKeychainFallback(_ configuration: AIConfiguration) throws -> AIConfiguration {
        var resolvedConfiguration = configuration
        resolvedConfiguration.openAIApiKey = try keychain.readValue(for: Constants.openAIApiKey)
        return resolvedConfiguration
    }

    private func storeConfigurationWithoutSecrets(_ configuration: AIConfiguration) throws {
        var sanitizedConfiguration = configuration
        sanitizedConfiguration.openAIApiKey = nil
        let data = try encoder.encode(sanitizedConfiguration)
        defaults.set(data, forKey: Constants.configurationKey)
    }

    private func storeAPIKey(_ apiKey: String?) throws {
        try keychain.save(apiKey, for: Constants.openAIApiKey)
    }
}
