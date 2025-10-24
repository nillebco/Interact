import Foundation

enum OllamaClientError: Error, LocalizedError {
    case invalidHost(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidHost(let host):
            return "Unable to build Ollama URL for host \(host)."
        case .invalidResponse:
            return "Ollama returned an unexpected response."
        }
    }
}

protocol OllamaClientProtocol {
    func checkAvailability(host: String, port: Int) async -> Bool
    func listModels(host: String, port: Int) async throws -> [AIModel]
    func generateResponse(
        host: String,
        port: Int,
        model: String,
        messages: [AIMessage]
    ) async throws -> String
}

struct OllamaClient: OllamaClientProtocol {
    private let session: URLSession
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    private let encoder = JSONEncoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func checkAvailability(host: String, port: Int) async -> Bool {
        guard let url = resolveURL(host: host, port: port, path: "/api/tags") else {
            return false
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return (200..<300).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }

    func listModels(host: String, port: Int) async throws -> [AIModel] {
        let requestURL = try url(host: host, port: port, path: "/api/tags")
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw OllamaClientError.invalidResponse
        }

        let apiResponse = try decoder.decode(OllamaListResponse.self, from: data)
        return apiResponse.models.map { model in
            AIModel(
                id: model.name,
                name: model.name,
                provider: .ollama,
                contextLength: nil
            )
        }
    }

    func generateResponse(
        host: String,
        port: Int,
        model: String,
        messages: [AIMessage]
    ) async throws -> String {
        let requestURL = try url(host: host, port: port, path: "/api/chat")
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = OllamaChatRequest(
            model: model,
            messages: messages.map { .init(role: $0.role.rawValue, content: $0.content) },
            stream: false
        )
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw OllamaClientError.invalidResponse
        }

        let apiResponse = try decoder.decode(OllamaChatResponse.self, from: data)
        guard let content = apiResponse.message?.content else {
            throw OllamaClientError.invalidResponse
        }
        return content
    }

    private func url(host: String, port: Int, path: String) throws -> URL {
        guard let url = resolveURL(host: host, port: port, path: path) else {
            throw OllamaClientError.invalidHost(host)
        }
        return url
    }

    private func resolveURL(host: String, port: Int, path: String) -> URL? {
        if var components = URLComponents(string: host) {
            if components.scheme == nil {
                components.scheme = "http"
            }
            components.port = port
            components.path = path
            return components.url
        }

        var fallbackComponents = URLComponents()
        fallbackComponents.scheme = "http"
        fallbackComponents.host = host
        fallbackComponents.port = port
        fallbackComponents.path = path
        return fallbackComponents.url
    }
}

private struct OllamaListResponse: Decodable {
    struct Model: Decodable {
        let name: String
    }

    let models: [Model]
}

private struct OllamaChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let stream: Bool
}

private struct OllamaChatResponse: Decodable {
    struct Message: Decodable {
        let content: String?
    }

    let message: Message?
}
