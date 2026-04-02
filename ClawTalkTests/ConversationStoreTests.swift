import Testing
import Foundation
@testable import ClawTalk

@Suite("Conversation Store")
struct ConversationStoreTests {
    private let store = ConversationStore.shared

    private func makeChannel() -> UUID {
        UUID()
    }

    // MARK: - Save & Load

    @Test("Save and load round-trips messages")
    func saveLoadRoundTrip() {
        let channelId = makeChannel()
        let messages = [
            Message(role: .user, content: "Hello"),
            Message(role: .assistant, content: "Hi there!"),
        ]

        store.save(messages, channelId: channelId)
        let loaded = store.load(channelId: channelId)

        #expect(loaded.count == 2)
        #expect(loaded[0].role == .user)
        #expect(loaded[0].content == "Hello")
        #expect(loaded[1].role == .assistant)
        #expect(loaded[1].content == "Hi there!")

        // Cleanup
        store.clear(channelId: channelId)
    }

    @Test("Loading non-existent channel returns empty array")
    func loadEmpty() {
        let channelId = makeChannel()
        let loaded = store.load(channelId: channelId)
        #expect(loaded.isEmpty)
    }

    @Test("Streaming messages are saved with isStreaming reset to false")
    func savesStreamingMessagesWithFlagReset() {
        let channelId = makeChannel()
        let messages = [
            Message(role: .user, content: "Hello"),
            Message(role: .assistant, content: "Partial...", isStreaming: true),
            Message(role: .assistant, content: "Complete response"),
        ]

        store.save(messages, channelId: channelId)
        let loaded = store.load(channelId: channelId)

        #expect(loaded.count == 3)
        #expect(loaded[0].content == "Hello")
        #expect(loaded[1].content == "Partial...")
        #expect(loaded[1].isStreaming == false)
        #expect(loaded[2].content == "Complete response")

        store.clear(channelId: channelId)
    }

    @Test("Empty content messages are filtered out on save")
    func filtersEmptyMessages() {
        let channelId = makeChannel()
        let messages = [
            Message(role: .user, content: "Hello"),
            Message(role: .assistant, content: ""),
        ]

        store.save(messages, channelId: channelId)
        let loaded = store.load(channelId: channelId)

        #expect(loaded.count == 1)
        #expect(loaded[0].content == "Hello")

        store.clear(channelId: channelId)
    }

    @Test("isStreaming is reset to false on load")
    func resetsStreamingFlag() {
        let channelId = makeChannel()
        // Save a completed message (non-streaming, non-empty)
        let messages = [
            Message(role: .assistant, content: "Done"),
        ]

        store.save(messages, channelId: channelId)
        let loaded = store.load(channelId: channelId)

        #expect(loaded.count == 1)
        #expect(loaded[0].isStreaming == false)

        store.clear(channelId: channelId)
    }

    @Test("Clear removes channel conversation")
    func clearChannel() {
        let channelId = makeChannel()
        store.save([Message(role: .user, content: "test")], channelId: channelId)

        store.clear(channelId: channelId)
        let loaded = store.load(channelId: channelId)

        #expect(loaded.isEmpty)
    }

    @Test("Messages with token usage persist")
    func tokenUsagePersists() {
        let channelId = makeChannel()
        var msg = Message(role: .assistant, content: "The answer is 42.")
        msg.tokenUsage = TokenUsage(inputTokens: 15, outputTokens: 8, totalTokens: 23)
        msg.responseId = "resp_abc"
        msg.modelName = "claude-sonnet"

        store.save([msg], channelId: channelId)
        let loaded = store.load(channelId: channelId)

        #expect(loaded.count == 1)
        #expect(loaded[0].tokenUsage?.outputTokens == 8)
        #expect(loaded[0].responseId == "resp_abc")
        #expect(loaded[0].modelName == "claude-sonnet")

        store.clear(channelId: channelId)
    }

    @Test("Messages with images persist")
    func imageDataPersists() {
        let channelId = makeChannel()
        let fakeImage = Data([0xFF, 0xD8, 0xFF, 0xE0]) // JPEG magic bytes
        let msg = Message(role: .user, content: "Look at this", imageData: [fakeImage])

        store.save([msg], channelId: channelId)
        let loaded = store.load(channelId: channelId)

        #expect(loaded.count == 1)
        #expect(loaded[0].hasImages == true)
        #expect(loaded[0].imageData?.first == fakeImage)

        store.clear(channelId: channelId)
    }

    @Test("Multiple channels are independent")
    func channelIsolation() {
        let ch1 = makeChannel()
        let ch2 = makeChannel()

        store.save([Message(role: .user, content: "Channel 1")], channelId: ch1)
        store.save([Message(role: .user, content: "Channel 2")], channelId: ch2)

        let loaded1 = store.load(channelId: ch1)
        let loaded2 = store.load(channelId: ch2)

        #expect(loaded1.count == 1)
        #expect(loaded1[0].content == "Channel 1")
        #expect(loaded2.count == 1)
        #expect(loaded2[0].content == "Channel 2")

        store.clear(channelId: ch1)
        store.clear(channelId: ch2)
    }
}
