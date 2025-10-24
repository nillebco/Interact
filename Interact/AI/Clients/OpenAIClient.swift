import Foundation

enum OpenAIClientError: Error, LocalizedError {
    case missingAPIKey
    case emptyResponse
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "An OpenAI API key is required."
        case .emptyResponse:
            return "The OpenAI response did not include any content."
        case .invalidResponse:
            return "OpenAI returned an unexpected response."
        }
    }
}

protocol OpenAIClientProtocol {
    func checkAvailability(apiKey: String?, endpoint: String) async -> Bool
    func listModels(apiKey: String, endpoint: String) async throws -> [AIModel]
    func generateResponse(
        apiKey: String,
        endpoint: String,
        model: String,
        messages: [AIMessage],
        tools: [AITool]
    ) async throws -> String
}

struct OpenAIClient: OpenAIClientProtocol {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func checkAvailability(apiKey: String?, endpoint: String) async -> Bool {
        guard let apiKey, apiKey.isEmpty == false else {
            return false
        }

        do {
            _ = try await listModels(apiKey: apiKey, endpoint: endpoint)
            return true
        } catch {
            return false
        }
    }

    func listModels(apiKey: String, endpoint: String) async throws -> [AIModel] {
        guard apiKey.isEmpty == false else {
            throw OpenAIClientError.missingAPIKey
        }

        let requestURL = try makeURL(endpoint: endpoint, path: "/v1/models")
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw OpenAIClientError.invalidResponse
        }

        let apiResponse = try decoder.decode(OpenAIModelListResponse.self, from: data)
        return apiResponse.data
            .filter { $0.id.lowercased().contains("gpt") }
            .map { model in
                AIModel(
                    id: model.id,
                    name: model.id,
                    provider: .openAI,
                    contextLength: contextWindow(for: model.id)
                )
            }
    }

    func generateResponse(
        apiKey: String,
        endpoint: String,
        model: String,
        messages: [AIMessage],
        tools: [AITool]
    ) async throws -> String {
        guard apiKey.isEmpty == false else {
            throw OpenAIClientError.missingAPIKey
        }

        let requestURL = try makeURL(endpoint: endpoint, path: "/v1/chat/completions")
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let payload = OpenAIChatRequest(
            model: model,
            messages: messages.map { .init(role: $0.role.rawValue, content: $0.content) },
            temperature: 0.7,
            tools: tools.isEmpty ? nil : tools.map { OpenAIToolDefinition(tool: $0) }
        )
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw OpenAIClientError.invalidResponse
        }

        let apiResponse = try decoder.decode(OpenAIChatResponse.self, from: data)
        guard let choice = apiResponse.choices.first else {
            throw OpenAIClientError.emptyResponse
        }
        return choice.message.content
    }

    private func makeURL(endpoint: String, path: String) throws -> URL {
        guard var components = URLComponents(string: endpoint) else {
            throw OpenAIClientError.invalidResponse
        }
        if components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        components.path += path
        guard let url = components.url else {
            throw OpenAIClientError.invalidResponse
        }
        return url
    }

    private func contextWindow(for modelId: String) -> Int? {
        if modelId.contains("gpt-4") {
            return 128_000
        }
        if modelId.contains("gpt-3.5") {
            return 16_000
        }
        return nil
    }
}

private struct OpenAIModelListResponse: Decodable {
    struct Model: Decodable {
        let id: String
    }

    let data: [Model]
}

private struct OpenAIChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let tools: [OpenAIToolDefinition]?
}

private struct OpenAIChatResponse: Decodable {
    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let string = try? container.decode(String.self, forKey: .content) {
                content = string
                return
            }

            var unkeyedContainer = try container.nestedUnkeyedContainer(forKey: .content)
            var collected = ""
            while !unkeyedContainer.isAtEnd {
                let block = try unkeyedContainer.decode(MessageContent.self)
                if let text = block.text?.value {
                    collected.append(text)
                }
            }
            content = collected
        }

        private enum CodingKeys: String, CodingKey {
            case content
        }
    }

    struct MessageContent: Decodable {
        struct Text: Decodable {
            let value: String
        }

        let type: String
        let text: Text?
    }

    let choices: [Choice]
}

private struct OpenAIToolDefinition: Encodable {
    struct Function: Encodable {
        struct Parameters: Encodable {
            let type = "object"
            let properties: [String: Property]
            let required: [String]

            struct Property: Encodable {
                let type: String
                let description: String
            }
        }

        let name: String
        let description: String
        let parameters: Parameters
    }

    let type = "function"
    let function: Function

    init(tool: AITool) {
        let properties = Dictionary(uniqueKeysWithValues: tool.parameters.map { parameter in
            let type: String = parameter.type == .boolean ? "boolean" : "string"
            return (parameter.name, Function.Parameters.Property(type: type, description: parameter.description))
        })
        let required = tool.parameters.filter { $0.required }.map { $0.name }
        self.function = Function(
            name: tool.name,
            description: tool.summary,
            parameters: .init(properties: properties, required: required)
        )
    }
}
