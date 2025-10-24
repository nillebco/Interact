import Foundation

struct AITool: Identifiable, Equatable, Codable {
    enum ParameterType: String, Codable {
        case string
        case boolean
    }

    struct Parameter: Equatable, Codable {
        let name: String
        let type: ParameterType
        let description: String
        let required: Bool
    }

    let id: String
    let name: String
    let summary: String
    let parameters: [Parameter]

    init(name: String, summary: String, parameters: [Parameter]) {
        self.id = name
        self.name = name
        self.summary = summary
        self.parameters = parameters
    }
}

struct AIToolInvocation: Codable {
    let name: String
    let arguments: [String: String]
}
