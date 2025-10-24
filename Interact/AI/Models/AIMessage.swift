import Foundation

struct AIMessage: Equatable, Codable {
    enum Role: String, Codable {
        case system
        case user
        case assistant
    }

    enum Component: Equatable, Codable {
        case text(String)
        case imageDataURL(String)

        private enum CodingKeys: String, CodingKey {
            case type
            case text
            case imageURL = "image_url"
        }

        private enum ComponentType: String, Codable {
            case text
            case imageURL = "image_url"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let value):
                try container.encode(ComponentType.text, forKey: .type)
                try container.encode(value, forKey: .text)
            case .imageDataURL(let value):
                try container.encode(ComponentType.imageURL, forKey: .type)
                try container.encode(["url": value], forKey: .imageURL)
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(ComponentType.self, forKey: .type)
            switch type {
            case .text:
                self = .text(try container.decode(String.self, forKey: .text))
            case .imageURL:
                let payload = try container.decode([String: String].self, forKey: .imageURL)
                self = .imageDataURL(payload["url"] ?? "")
            }
        }

        var asString: String? {
            if case .text(let value) = self { return value }
            return nil
        }
    }

    let role: Role
    let components: [Component]

    init(role: Role, components: [Component]) {
        self.role = role
        self.components = components
    }

    init(role: Role, content: String) {
        self.role = role
        self.components = [.text(content)]
    }

    var primaryText: String? {
        if components.count == 1, case let .text(text) = components.first { return text }
        return nil
    }
}
