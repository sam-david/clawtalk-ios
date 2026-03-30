import SwiftUI

/// Renders a JSON string with syntax coloring and proper formatting.
struct JSONPrettyView: View {
    let jsonString: String

    var body: some View {
        if let formatted = Self.prettyFormat(jsonString) {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    let lines = formatted.components(separatedBy: "\n")
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        SyntaxColoredJSON(text: line)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .textSelection(.enabled)
                .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            // Fallback: plain text
            Text(jsonString)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private static func prettyFormat(_ raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8)
        else { return nil }
        return str.replacingOccurrences(of: "\\/", with: "/")
    }
}

/// Renders JSON text with syntax coloring using AttributedString.
private struct SyntaxColoredJSON: View {
    let text: String

    var body: some View {
        Text(colorized)
            .font(.system(.caption, design: .monospaced))
    }

    private var colorized: AttributedString {
        var result = AttributedString()

        var i = text.startIndex
        while i < text.endIndex {
            let ch = text[i]

            if ch == "\"" {
                // Find the closing quote
                let start = i
                let afterQuote = text.index(after: i)
                if let closeQuote = text[afterQuote...].firstIndex(of: "\"") {
                    let stringEnd = text.index(after: closeQuote)
                    let fullString = String(text[start..<stringEnd])
                    let inner = String(text[afterQuote..<closeQuote])

                    // Check if this is a key (followed by " :")
                    let afterClose = stringEnd
                    let remaining = text[afterClose...].drop(while: { $0 == " " })
                    let isKey = remaining.first == ":"

                    var part = AttributedString(fullString)
                    if isKey {
                        part.foregroundColor = .init(red: 0.6, green: 0.8, blue: 1.0) // light blue for keys
                    } else if inner.hasPrefix("http://") || inner.hasPrefix("https://") || inner.hasPrefix("/") {
                        part.foregroundColor = .init(red: 0.55, green: 0.85, blue: 0.55) // green for paths/URLs
                    } else {
                        part.foregroundColor = .init(red: 1.0, green: 0.7, blue: 0.4) // orange for string values
                    }
                    result += part
                    i = stringEnd
                    continue
                }
            }

            // Booleans and null
            let remaining = text[i...]
            if let match = matchKeyword(remaining, "true") ?? matchKeyword(remaining, "false") {
                var part = AttributedString(match)
                part.foregroundColor = .init(red: 0.8, green: 0.6, blue: 1.0) // purple for booleans
                result += part
                i = text.index(i, offsetBy: match.count)
                continue
            }
            if let match = matchKeyword(remaining, "null") {
                var part = AttributedString(match)
                part.foregroundColor = .init(red: 0.6, green: 0.6, blue: 0.6) // grey for null
                result += part
                i = text.index(i, offsetBy: match.count)
                continue
            }

            // Numbers
            if ch.isNumber || (ch == "-" && text.index(after: i) < text.endIndex && text[text.index(after: i)].isNumber) {
                var numEnd = text.index(after: i)
                while numEnd < text.endIndex && (text[numEnd].isNumber || text[numEnd] == "." || text[numEnd] == "e" || text[numEnd] == "E") {
                    numEnd = text.index(after: numEnd)
                }
                var part = AttributedString(String(text[i..<numEnd]))
                part.foregroundColor = .init(red: 0.85, green: 0.85, blue: 0.5) // yellow for numbers
                result += part
                i = numEnd
                continue
            }

            // Structural characters and whitespace
            var part = AttributedString(String(ch))
            if ch == "{" || ch == "}" || ch == "[" || ch == "]" || ch == ":" || ch == "," {
                part.foregroundColor = .init(red: 0.7, green: 0.7, blue: 0.7) // grey for structure
            } else {
                part.foregroundColor = .init(red: 0.7, green: 0.7, blue: 0.7)
            }
            result += part
            i = text.index(after: i)
        }

        return result
    }

    private func matchKeyword(_ text: Substring, _ keyword: String) -> String? {
        guard text.hasPrefix(keyword) else { return nil }
        let afterIdx = text.index(text.startIndex, offsetBy: keyword.count)
        if afterIdx >= text.endIndex { return keyword }
        let after = text[afterIdx]
        // Keyword must be followed by a non-alphanumeric char
        if after.isLetter || after.isNumber { return nil }
        return keyword
    }
}
