import Foundation

struct Channel: Identifiable, Codable {
    let id: UUID
    var name: String
    var agentId: String
    var systemEmoji: String
    let createdAt: Date
    var sessionVersion: Int

    init(name: String, agentId: String, systemEmoji: String = "🤖") {
        self.id = UUID()
        self.name = name
        self.agentId = agentId
        self.systemEmoji = systemEmoji
        self.createdAt = Date()
        self.sessionVersion = 0
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        agentId = try container.decode(String.self, forKey: .agentId)
        systemEmoji = try container.decode(String.self, forKey: .systemEmoji)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        sessionVersion = try container.decodeIfPresent(Int.self, forKey: .sessionVersion) ?? 0
    }

    /// The model string to send to the OpenClaw gateway.
    var modelString: String {
        "openclaw:\(agentId)"
    }

    static let `default` = Channel(name: "Main", agentId: "main", systemEmoji: "🦞")
}
