import Foundation

struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let user: String?

    struct ChatMessage: Encodable {
        let role: String
        let content: String
    }
}

struct ChatCompletionChunk: Decodable {
    let id: String?
    let choices: [Choice]

    struct Choice: Decodable {
        let delta: Delta?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct Delta: Decodable {
        let content: String?
        let role: String?
    }
}

struct ChatCompletionResponse: Decodable {
    let id: String
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ResponseMessage
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    struct ResponseMessage: Decodable {
        let role: String
        let content: String?
    }
}
