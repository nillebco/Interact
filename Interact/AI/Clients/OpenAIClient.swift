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
    ) async throws -> AIResponse
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
    ) async throws -> AIResponse {
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
            messages: messages.map { OpenAIChatRequest.Message(message: $0) },
            tools: tools.isEmpty ? nil : tools.map { OpenAIToolDefinition(tool: $0) }
        )
        let bodyData = try encoder.encode(payload)
        print("[OpenAI] Request:\n\(String(data: bodyData, encoding: .utf8) ?? "<invalid>")")
        request.httpBody = bodyData

        let (data, response) = try await session.data(for: request)
        print("[OpenAI] Response status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        if let bodyString = String(data: data, encoding: .utf8) {
            print("[OpenAI] Response body:\n\(bodyString)")
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw OpenAIClientError.invalidResponse
        }

        let apiResponse = try decoder.decode(OpenAIChatResponse.self, from: data)
        guard let choice = apiResponse.choices.first else {
            throw OpenAIClientError.emptyResponse
        }

        let message = choice.message
        let content = message.content?.trimmingCharacters(in: .whitespacesAndNewlines)

        var toolInvocations: [AIToolInvocation] = []
        if let toolCalls = message.toolCalls {
            toolInvocations = toolCalls.compactMap(convertToolCall)
        }

        if toolInvocations.isEmpty, let content,
           let fallbackInvocation = parseInlineToolInvocation(from: content) {
            toolInvocations = [fallbackInvocation]
        }

        return AIResponse(text: content, toolInvocations: toolInvocations)
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

    private func convertToolCall(_ toolCall: OpenAIChatResponse.ToolCall) -> AIToolInvocation? {
        let argumentsString = toolCall.function.arguments
        guard let data = argumentsString.data(using: .utf8) else {
            return nil
        }

        guard let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let stringified = dictionary.reduce(into: [String: String]()) { partialResult, element in
            switch element.value {
            case let string as String:
                partialResult[element.key] = string
            case let number as NSNumber:
                if CFBooleanGetTypeID() == CFGetTypeID(number) {
                    partialResult[element.key] = number.boolValue ? "true" : "false"
                } else {
                    partialResult[element.key] = number.stringValue
                }
            default:
                partialResult[element.key] = "\(element.value)"
            }
        }

        return AIToolInvocation(name: toolCall.function.name, arguments: stringified)
    }

    private func parseInlineToolInvocation(from content: String) -> AIToolInvocation? {
        guard let data = content.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(AIToolInvocation.self, from: data)
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
        let components: [AIMessage.Component]

        init(message: AIMessage) {
            self.role = message.role.rawValue
            self.components = message.components
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(role, forKey: .role)

            if components.count == 1, let text = components.first?.asString {
                try container.encode(text, forKey: .content)
            } else {
                var array = container.nestedUnkeyedContainer(forKey: .content)
                for component in components {
                    var partContainer = array.nestedContainer(keyedBy: PartCodingKeys.self)
                    switch component {
                    case .text(let text):
                        try partContainer.encode("text", forKey: .type)
                        try partContainer.encode(text, forKey: .text)
                    case .imageDataURL(let dataURL):
                        try partContainer.encode("image_url", forKey: .type)
                        try partContainer.encode(["url": dataURL], forKey: .imageURL)
                    }
                }
            }
        }

        private enum CodingKeys: String, CodingKey {
            case role
            case content
        }

        private enum PartCodingKeys: String, CodingKey {
            case type
            case text
            case imageURL = "image_url"
        }
    }

    let model: String
    let messages: [Message]
    let tools: [OpenAIToolDefinition]?
}

private struct OpenAIChatResponse: Decodable {
    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
        let toolCalls: [ToolCall]?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            if let string = try? container.decode(String.self, forKey: .content) {
                content = string
            } else if var arrayContainer = try? container.nestedUnkeyedContainer(forKey: .content) {
                var collected = ""
                while !arrayContainer.isAtEnd {
                    let block = try arrayContainer.decode(MessageContent.self)
                    if let text = block.text?.value {
                        collected.append(text)
                    }
                }
                content = collected.isEmpty ? nil : collected
            } else {
                content = nil
            }

            toolCalls = try container.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
        }

        private enum CodingKeys: String, CodingKey {
            case content
            case toolCalls = "tool_calls"
        }
    }

    struct MessageContent: Decodable {
        struct Text: Decodable {
            let value: String
        }

        let type: String
        let text: Text?
    }

    struct ToolCall: Decodable {
        struct Function: Decodable {
            let name: String
            let arguments: String
        }

        let function: Function
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
