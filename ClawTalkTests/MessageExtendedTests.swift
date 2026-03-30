import Testing
import Foundation
@testable import ClawTalk

@Suite("Message Model — Extended")
struct MessageExtendedTests {

    // MARK: - Computed Properties

    @Test("hasImages returns false when imageData is nil")
    func hasImagesNil() {
        let msg = Message(role: .user, content: "text")
        #expect(msg.hasImages == false)
    }

    @Test("hasImages returns false when imageData is empty")
    func hasImagesEmpty() {
        let msg = Message(role: .user, content: "text", imageData: [])
        #expect(msg.hasImages == false)
    }

    @Test("hasImages returns true when imageData has items")
    func hasImagesPresent() {
        let msg = Message(role: .user, content: "text", imageData: [Data([1, 2, 3])])
        #expect(msg.hasImages == true)
    }

    @Test("hasFailed returns false by default")
    func hasFailedDefault() {
        let msg = Message(role: .user, content: "text")
        #expect(msg.hasFailed == false)
    }

    @Test("hasFailed returns true when sendError is set")
    func hasFailedWithError() {
        var msg = Message(role: .user, content: "text")
        msg.sendError = "Connection refused"
        #expect(msg.hasFailed == true)
    }

    // MARK: - Codable with all fields

    @Test("Message with all optional fields round-trips")
    func fullRoundTrip() throws {
        var msg = Message(role: .assistant, content: "Response text")
        msg.tokenUsage = TokenUsage(inputTokens: 50, outputTokens: 100, totalTokens: 150)
        msg.responseId = "resp_xyz"
        msg.modelName = "claude-opus"
        msg.sendError = nil

        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(Message.self, from: data)

        #expect(decoded.content == "Response text")
        #expect(decoded.tokenUsage?.inputTokens == 50)
        #expect(decoded.responseId == "resp_xyz")
        #expect(decoded.modelName == "claude-opus")
        #expect(decoded.sendError == nil)
    }

    @Test("Message with sendError round-trips")
    func sendErrorRoundTrip() throws {
        var msg = Message(role: .user, content: "Failed message")
        msg.sendError = "HTTP 500"

        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(Message.self, from: data)

        #expect(decoded.sendError == "HTTP 500")
        #expect(decoded.hasFailed == true)
    }

    @Test("Old messages without modelName/sendError decode correctly")
    func backwardCompatibilityNewFields() throws {
        let oldJSON = """
        {
            "id": "550E8400-E29B-41D4-A716-446655440000",
            "role": "assistant",
            "content": "Old message",
            "timestamp": 1709827200,
            "isStreaming": false
        }
        """

        let decoded = try JSONDecoder().decode(Message.self, from: oldJSON.data(using: .utf8)!)

        #expect(decoded.content == "Old message")
        #expect(decoded.modelName == nil)
        #expect(decoded.sendError == nil)
        #expect(decoded.tokenUsage == nil)
        #expect(decoded.imageData == nil)
    }

    // MARK: - Roles

    @Test("MessageRole raw values")
    func roleRawValues() {
        #expect(MessageRole.user.rawValue == "user")
        #expect(MessageRole.assistant.rawValue == "assistant")
    }

    @Test("MessageRole decodes from string")
    func roleDecoding() throws {
        let json = "\"user\""
        let decoded = try JSONDecoder().decode(MessageRole.self, from: json.data(using: .utf8)!)
        #expect(decoded == .user)
    }
}
