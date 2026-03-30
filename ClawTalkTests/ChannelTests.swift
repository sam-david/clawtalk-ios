import Testing
import Foundation
@testable import ClawTalk

@Suite("Channel Model")
struct ChannelTests {

    // MARK: - Initialization

    @Test("Channel initializes with correct defaults")
    func channelDefaults() {
        let channel = Channel(name: "Test", agentId: "coder")

        #expect(channel.name == "Test")
        #expect(channel.agentId == "coder")
        #expect(channel.systemEmoji == "🤖")
        #expect(channel.sessionVersion == 0)
        #expect(channel.selectedModel == nil)
    }

    @Test("Default channel is Main with lobster emoji")
    func defaultChannel() {
        let channel = Channel.default

        #expect(channel.name == "Main")
        #expect(channel.agentId == "main")
        #expect(channel.systemEmoji == "🦞")
    }

    @Test("Each channel gets a unique ID")
    func uniqueIDs() {
        let a = Channel(name: "A", agentId: "main")
        let b = Channel(name: "B", agentId: "main")
        #expect(a.id != b.id)
    }

    // MARK: - Model String

    @Test("modelString formats as openclaw:{agentId}")
    func modelString() {
        let channel = Channel(name: "Test", agentId: "coder")
        #expect(channel.modelString == "openclaw:coder")
    }

    @Test("modelString with default agent")
    func modelStringDefault() {
        let channel = Channel.default
        #expect(channel.modelString == "openclaw:main")
    }

    // MARK: - Codable

    @Test("Channel round-trips through JSON")
    func codableRoundTrip() throws {
        let original = Channel(name: "Research", agentId: "research", systemEmoji: "🔬")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Channel.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == "Research")
        #expect(decoded.agentId == "research")
        #expect(decoded.systemEmoji == "🔬")
        #expect(decoded.sessionVersion == 0)
    }

    @Test("Old channel JSON without sessionVersion decodes with default 0")
    func backwardCompatibility() throws {
        let oldJSON = """
        {
            "id": "550E8400-E29B-41D4-A716-446655440000",
            "name": "Legacy",
            "agentId": "main",
            "systemEmoji": "🤖",
            "createdAt": 1709827200
        }
        """

        let decoded = try JSONDecoder().decode(Channel.self, from: oldJSON.data(using: .utf8)!)

        #expect(decoded.name == "Legacy")
        #expect(decoded.sessionVersion == 0)
        #expect(decoded.selectedModel == nil)
    }

    @Test("Channel with selectedModel round-trips")
    func selectedModelRoundTrip() throws {
        var channel = Channel(name: "Test", agentId: "main")
        channel.selectedModel = "anthropic/claude-sonnet"

        let data = try JSONEncoder().encode(channel)
        let decoded = try JSONDecoder().decode(Channel.self, from: data)

        #expect(decoded.selectedModel == "anthropic/claude-sonnet")
    }
}
