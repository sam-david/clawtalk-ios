import Foundation

// MARK: - JSON Value (for heterogeneous tool args)

enum JSONValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .null: try container.encodeNil()
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? container.decode(Int.self) {
            self = .int(v)
        } else if let v = try? container.decode(Double.self) {
            self = .double(v)
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else if let v = try? container.decode([JSONValue].self) {
            self = .array(v)
        } else if let v = try? container.decode([String: JSONValue].self) {
            self = .object(v)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode JSONValue")
        }
    }
}

// MARK: - Tool Invoke Request

struct ToolInvokeRequest: Encodable {
    let tool: String
    let action: String?
    let args: [String: JSONValue]?
    let sessionKey: String?
}

// MARK: - Tool Invoke Response

struct ToolInvokeResponse: Decodable {
    let ok: Bool
    let result: JSONValue?
    let error: ToolInvokeError?
}

struct ToolInvokeError: Decodable {
    let type: String?
    let message: String?
}

/// Tools return {content: [...], details: {...}} where details holds structured data.
struct ToolResultWrapper<T: Decodable>: Decodable {
    let content: [ToolContentItem]?
    let details: T?
}

struct ToolContentItem: Decodable {
    let type: String
    let text: String?
    let image: ToolImageContent?
}

struct ToolImageContent: Decodable {
    let data: String?
    let mediaType: String?

    enum CodingKeys: String, CodingKey {
        case data
        case mediaType = "media_type"
    }
}

// MARK: - Memory Types

struct MemorySearchResults: Decodable {
    let results: [MemorySearchEntry]
    let provider: String?
    let model: String?
}

struct MemorySearchEntry: Decodable, Identifiable {
    var id: String { "\(path):\(startLine)" }
    let path: String
    let snippet: String
    let score: Double
    let startLine: Int
    let endLine: Int
    let source: String?

    enum CodingKeys: String, CodingKey {
        case path, snippet, score, source
        case startLine = "startLine"
        case endLine = "endLine"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        snippet = try container.decode(String.self, forKey: .snippet)
        score = try container.decode(Double.self, forKey: .score)
        startLine = try container.decodeIfPresent(Int.self, forKey: .startLine) ?? 0
        endLine = try container.decodeIfPresent(Int.self, forKey: .endLine) ?? 0
        source = try container.decodeIfPresent(String.self, forKey: .source)
    }
}

struct MemoryGetResult: Decodable {
    let path: String
    let text: String
    let disabled: Bool?
    let error: String?
}

// MARK: - Session Types

struct SessionsListResult: Decodable {
    let count: Int
    let sessions: [SessionEntry]
}

struct SessionEntry: Decodable, Identifiable {
    var id: String { key }
    let key: String
    let kind: String?
    let channel: String?
    let label: String?
    let displayName: String?
    let updatedAt: Double?
    let model: String?
    let contextTokens: Int?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case key, kind, channel, label, model
        case displayName = "displayName"
        case updatedAt = "updatedAt"
        case contextTokens = "contextTokens"
        case totalTokens = "totalTokens"
    }
}

// MARK: - Session Status

struct SessionStatusResult: Decodable {
    let content: [ContentItem]?
    let details: StatusDetails?

    struct ContentItem: Decodable {
        let type: String
        let text: String?
    }

    struct StatusDetails: Decodable {
        let ok: Bool?
        let sessionKey: String?
        let statusText: String?
    }
}

// MARK: - Agents Types

struct AgentsListResult: Decodable {
    let requester: String?
    let allowAny: Bool?
    let agents: [AgentEntry]
}

struct AgentEntry: Decodable, Identifiable {
    var id: String { agentId }
    let agentId: String
    let configured: Bool?

    enum CodingKeys: String, CodingKey {
        case agentId = "id"
        case configured
    }
}

// MARK: - Session History Types

struct SessionHistoryResult: Decodable {
    let sessionKey: String?
    let messages: [SessionHistoryMessage]
    let truncated: Bool?
    let bytes: Int?
}

struct SessionHistoryMessage: Decodable, Identifiable {
    var id: String { "\(role)-\(timestamp ?? 0)" }
    let role: String
    let content: [SessionHistoryContent]
    let model: String?
    let provider: String?
    let stopReason: String?
    let timestamp: Double?
}

struct SessionHistoryContent: Decodable {
    let type: String
    let text: String?
    let thinking: String?
    let name: String?
}

// MARK: - Browser Types

struct BrowserDetails: Decodable {
    let ok: Bool?
    let targetId: String?
    let url: String?
}

// typealias for browser results using generic wrapper
// Usage: ToolResultWrapper<BrowserDetails>
