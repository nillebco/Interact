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
    let requiresFollowUp: Bool

    init(name: String, summary: String, requiresFollowUp: Bool = false, parameters: [Parameter]) {
        self.id = name
        self.name = name
        self.summary = summary
        self.parameters = parameters
        self.requiresFollowUp = requiresFollowUp
    }
}

struct AIToolInvocation: Codable, Equatable {
    let name: String
    let arguments: [String: String]

    init(name: String, arguments: [String: String]) {
        self.name = name
        self.arguments = arguments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawName: String
        if let explicitName = try? container.decode(String.self, forKey: .name) {
            rawName = explicitName
        } else {
            rawName = try container.decode(String.self, forKey: .tool)
        }
        let rawArguments = try container.decode([String: ArgumentValue].self, forKey: .arguments)

        self.name = rawName
        self.arguments = rawArguments.mapValues { $0.stringValue }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        let encodableArguments = arguments.mapValues { ArgumentValue(stringValue: $0) }
        try container.encode(encodableArguments, forKey: .arguments)
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case tool
        case arguments
    }

    private struct ArgumentValue: Codable {
        let stringValue: String

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                stringValue = string
            } else if let bool = try? container.decode(Bool.self) {
                stringValue = bool ? "true" : "false"
            } else if let int = try? container.decode(Int.self) {
                stringValue = String(int)
            } else if let double = try? container.decode(Double.self) {
                stringValue = String(double)
            } else {
                stringValue = ""
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(stringValue)
        }
    }
}
