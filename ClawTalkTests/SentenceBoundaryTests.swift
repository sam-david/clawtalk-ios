import Testing
@testable import ClawTalk

@Suite("Sentence Boundary Detection")
struct SentenceBoundaryTests {
    @Test("Detects period boundary")
    func periodBoundary() {
        let text = "Hello world. This is next"
        let boundary = text.lastSentenceBoundary()

        #expect(boundary != nil)
        let sentence = String(text.prefix(boundary!))
        #expect(sentence == "Hello world.")
    }

    @Test("Detects question mark boundary")
    func questionBoundary() {
        let text = "How are you? I am fine"
        let boundary = text.lastSentenceBoundary()

        #expect(boundary != nil)
        let sentence = String(text.prefix(boundary!))
        #expect(sentence == "How are you?")
    }

    @Test("Detects exclamation boundary")
    func exclamationBoundary() {
        let text = "That is amazing! Thanks"
        let boundary = text.lastSentenceBoundary()

        #expect(boundary != nil)
    }

    @Test("Returns nil for short text without boundary")
    func shortNoBoundary() {
        let text = "Hello"
        #expect(text.lastSentenceBoundary() == nil)
    }

    @Test("Returns nil for tiny fragment with period")
    func tinyFragment() {
        let text = "Hi. "
        // Should return nil because the fragment is < 10 chars
        #expect(text.lastSentenceBoundary() == nil)
    }

    @Test("Breaks long text at word boundary when no sentence terminator")
    func longTextWordBreak() {
        let text = String(repeating: "word ", count: 30) // 150 chars
        let boundary = text.lastSentenceBoundary()

        #expect(boundary != nil)
        let chunk = String(text.prefix(boundary!))
        #expect(chunk.last == " ")
        #expect(!chunk.isEmpty)
    }
}
