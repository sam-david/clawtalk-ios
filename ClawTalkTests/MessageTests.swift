import Testing
import Foundation
@testable import ClawTalk

@Suite("Message Model")
struct MessageTests {
    @Test("User message initializes with correct defaults")
    func userMessageDefaults() {
        let msg = Message(role: .user, content: "Hello agent")

        #expect(msg.role == .user)
        #expect(msg.content == "Hello agent")
        #expect(msg.isStreaming == false)
        #expect(msg.tokenUsage == nil)
        #expect(msg.responseId == nil)
    }

    @Test("Assistant streaming message")
    func assistantStreaming() {
        let msg = Message(role: .assistant, content: "", isStreaming: true)

        #expect(msg.role == .assistant)
        #expect(msg.isStreaming == true)
        #expect(msg.content.isEmpty)
    }

    @Test("Each message gets a unique ID")
    func uniqueIDs() {
        let a = Message(role: .user, content: "a")
        let b = Message(role: .user, content: "b")

        #expect(a.id != b.id)
    }

    @Test("Message is Codable")
    func codableRoundTrip() throws {
        let original = Message(role: .assistant, content: "Hello!")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Message.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.role == original.role)
        #expect(decoded.content == original.content)
        #expect(decoded.tokenUsage == nil)
        #expect(decoded.responseId == nil)
    }

    @Test("Message with token usage round-trips")
    func tokenUsageRoundTrip() throws {
        var msg = Message(role: .assistant, content: "The answer is 42.")
        msg.tokenUsage = TokenUsage(inputTokens: 15, outputTokens: 8, totalTokens: 23)
        msg.responseId = "resp_abc123"

        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(Message.self, from: data)

        #expect(decoded.tokenUsage?.inputTokens == 15)
        #expect(decoded.tokenUsage?.outputTokens == 8)
        #expect(decoded.tokenUsage?.totalTokens == 23)
        #expect(decoded.responseId == "resp_abc123")
    }

    @Test("Old saved messages without tokenUsage decode correctly")
    func backwardCompatibility() throws {
        // Simulate JSON from before tokenUsage/responseId fields existed
        let oldJSON = """
        {
            "id": "550E8400-E29B-41D4-A716-446655440000",
            "role": "assistant",
            "content": "Hello from the past!",
            "timestamp": 1709827200,
            "isStreaming": false
        }
        """

        let decoded = try JSONDecoder().decode(Message.self, from: oldJSON.data(using: .utf8)!)

        #expect(decoded.content == "Hello from the past!")
        #expect(decoded.tokenUsage == nil)
        #expect(decoded.responseId == nil)
        #expect(decoded.imageData == nil)
    }
}
