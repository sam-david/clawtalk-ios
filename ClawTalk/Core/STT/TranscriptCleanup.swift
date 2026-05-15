import Foundation

/// Strip Whisper-style meta tags (e.g. "[BLANK_AUDIO]", "[Silence]",
/// "[Music]") that occasionally leak into transcripts. We strip a small
/// allowlist rather than every `[...]` token so legitimate user content
/// like "[redacted]" or "[name]" survives.
enum TranscriptCleanup {
    private static let metaTagPattern: NSRegularExpression? = {
        let known = [
            "blank[_ ]audio",
            "no[_ ]speech",
            "silence",
            "pause",
            "music",
            "noise",
            "background[_ ]noise",
            "applause",
            "laughter",
            "inaudible",
        ]
        let alternation = known.joined(separator: "|")
        // Match "[ tag ]" with optional surrounding whitespace, case-insensitive.
        return try? NSRegularExpression(
            pattern: "\\s*\\[\\s*(?:\(alternation))\\s*\\]\\s*",
            options: [.caseInsensitive]
        )
    }()

    static func clean(_ raw: String) -> String {
        guard let regex = metaTagPattern else {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let range = NSRange(raw.startIndex..., in: raw)
        let stripped = regex.stringByReplacingMatches(
            in: raw,
            options: [],
            range: range,
            withTemplate: " "
        )
        // Collapse any double-spaces left behind.
        let collapsed = stripped.replacingOccurrences(
            of: "\\s{2,}",
            with: " ",
            options: .regularExpression
        )
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
