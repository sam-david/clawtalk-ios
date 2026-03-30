import Foundation

// MARK: - Request

struct OpenResponsesRequest: Encodable {
    let model: String
    let input: Input
    let stream: Bool
    let user: String?

    enum Input: Encodable {
        case text(String)
        case items([Item])

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let string):
                try container.encode(string)
            case .items(let items):
                try container.encode(items)
            }
        }
    }

    struct Item: Encodable {
        let type: String
        let role: String
        let content: ItemContent

        enum ItemContent: Encodable {
            case text(String)
            case parts([ContentPart])

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .text(let string):
                    try container.encode(string)
                case .parts(let parts):
                    try container.encode(parts)
                }
            }
        }
    }

    enum ContentPart: Encodable {
        case inputText(String)
        case inputImage(mediaType: String, base64Data: String)

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .inputText(let text):
                try container.encode("input_text", forKey: .type)
                try container.encode(text, forKey: .text)
            case .inputImage(let mediaType, let base64Data):
                try container.encode("input_image", forKey: .type)
                try container.encode(
                    Base64Source(mediaType: mediaType, data: base64Data),
                    forKey: .source
                )
            }
        }

        private enum CodingKeys: String, CodingKey {
            case type, text, source
        }

        private struct Base64Source: Encodable {
            let type = "base64"
            let mediaType: String
            let data: String

            enum CodingKeys: String, CodingKey {
                case type
                case mediaType = "media_type"
                case data
            }
        }
    }
}

// MARK: - SSE Event Decodables

/// Minimal decodable for `response.output_text.delta` SSE events.
struct ResponseTextDelta: Decodable {
    let delta: String
}

/// Minimal decodable for `response.completed` / `response.failed` SSE events.
struct ResponseCompleted: Decodable {
    let response: ResponseResource

    struct ResponseResource: Decodable {
        let id: String
        let model: String?
        let status: String
        let usage: Usage?
        let error: ResponseError?

        struct Usage: Decodable {
            let inputTokens: Int
            let outputTokens: Int
            let totalTokens: Int

            enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
                case totalTokens = "total_tokens"
            }
        }

        struct ResponseError: Decodable {
            let code: String
            let message: String
        }
    }
}
