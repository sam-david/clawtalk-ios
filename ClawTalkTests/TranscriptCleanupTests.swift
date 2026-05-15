import Testing
import Foundation
@testable import ClawTalk

@Suite("Transcript Cleanup")
struct TranscriptCleanupTests {

    @Test("Strips trailing [BLANK_AUDIO]")
    func stripsTrailingBlankAudio() {
        #expect(TranscriptCleanup.clean("Hello there [BLANK_AUDIO]") == "Hello there")
    }

    @Test("Strips lowercase variant")
    func stripsLowercase() {
        #expect(TranscriptCleanup.clean("Hello [blank_audio]") == "Hello")
    }

    @Test("Strips space-separated variant")
    func stripsSpaceSeparated() {
        #expect(TranscriptCleanup.clean("Hello [blank audio]") == "Hello")
    }

    @Test("Strips embedded tag")
    func stripsEmbeddedTag() {
        #expect(TranscriptCleanup.clean("Hello [SILENCE] there") == "Hello there")
    }

    @Test("Strips multiple tags")
    func stripsMultiple() {
        let raw = "[Music] One [silence] two [BLANK_AUDIO]"
        #expect(TranscriptCleanup.clean(raw) == "One two")
    }

    @Test("Strips Music, Pause, Noise, Applause, Laughter, Inaudible")
    func stripsKnownTags() {
        #expect(TranscriptCleanup.clean("a [Music] b") == "a b")
        #expect(TranscriptCleanup.clean("a [Pause] b") == "a b")
        #expect(TranscriptCleanup.clean("a [Noise] b") == "a b")
        #expect(TranscriptCleanup.clean("a [Applause] b") == "a b")
        #expect(TranscriptCleanup.clean("a [Laughter] b") == "a b")
        #expect(TranscriptCleanup.clean("a [inaudible] b") == "a b")
    }

    @Test("Trims surrounding whitespace")
    func trimsWhitespace() {
        #expect(TranscriptCleanup.clean("  hello  ") == "hello")
    }

    @Test("Empty input returns empty")
    func emptyInput() {
        #expect(TranscriptCleanup.clean("") == "")
        #expect(TranscriptCleanup.clean("   ") == "")
        #expect(TranscriptCleanup.clean("[BLANK_AUDIO]") == "")
    }

    @Test("Preserves user-authored bracketed text")
    func preservesUserContent() {
        // Tags not in the allowlist should survive.
        #expect(TranscriptCleanup.clean("Send to [redacted]") == "Send to [redacted]")
        #expect(TranscriptCleanup.clean("Hi [Bob], how are you?") == "Hi [Bob], how are you?")
    }

    @Test("Collapses double spaces left after a strip")
    func collapsesDoubleSpaces() {
        // "Hello  there" → "Hello there"
        #expect(TranscriptCleanup.clean("Hello [silence]  there") == "Hello there")
    }

    @Test("Tolerates tag with extra interior whitespace")
    func toleratesPaddedTag() {
        #expect(TranscriptCleanup.clean("Hello [  BLANK_AUDIO  ]") == "Hello")
    }
}
