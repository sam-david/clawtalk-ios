import Testing
@testable import OpenClawChat

@Suite("Message Model")
struct MessageTests {
    @Test("User message initializes with correct defaults")
    func userMessageDefaults() {
        let msg = Message(role: .user, content: "Hello agent")

        #expect(msg.role == .user)
        #expect(msg.content == "Hello agent")
        #expect(msg.isStreaming == false)
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
    }
}
