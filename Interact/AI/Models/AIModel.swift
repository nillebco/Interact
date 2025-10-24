import Foundation

struct AIModel: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    let provider: AIProvider
    let contextLength: Int?

    init(id: String, name: String, provider: AIProvider, contextLength: Int? = nil) {
        self.id = id
        self.name = name
        self.provider = provider
        self.contextLength = contextLength
    }
}
