import SwiftUI
import MarkdownUI

struct MessageBubble: View {
    let message: Message
    let onReplayAudio: (() -> Void)?
    var showTokenUsage: Bool
    let onRetry: (() -> Void)?
    let onDelete: (() -> Void)?

    init(message: Message, onReplayAudio: (() -> Void)? = nil, showTokenUsage: Bool = false, onRetry: (() -> Void)? = nil, onDelete: (() -> Void)? = nil) {
        self.message = message
        self.onReplayAudio = onReplayAudio
        self.showTokenUsage = showTokenUsage
        self.onRetry = onRetry
        self.onDelete = onDelete
    }

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                bubbleContent
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                HStack(spacing: 6) {
                    if isUser, message.hasFailed {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)

                        Text("Failed to send")
                            .font(.caption2)
                            .foregroundStyle(.red)

                        if let onRetry {
                            Button(action: onRetry) {
                                Text("Retry")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.openClawRed)
                            }
                        }
                    } else {
                        Text(message.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if !isUser, onReplayAudio != nil {
                            Button(action: { onReplayAudio?() }) {
                                Image(systemName: "speaker.wave.2")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if !isUser, showTokenUsage, let usage = message.tokenUsage {
                            Text("· \(usage.inputTokens)→\(usage.outputTokens) tokens")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
        .contextMenu {
            Button(action: {
                UIPasteboard.general.string = message.content
            }) {
                Label("Copy", systemImage: "doc.on.doc")
            }

            if let onDelete {
                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        if isUser {
            VStack(alignment: .leading, spacing: 8) {
                if message.hasImages, let images = message.imageData {
                    ForEach(Array(images.enumerated()), id: \.offset) { _, data in
                        if let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.body)
                        .foregroundStyle(.white)
                }
            }
        } else {
            if message.isStreaming && message.content.isEmpty {
                // Waiting for response — show typing dots
                TypingIndicator()
                    .padding(.top, 8)
                    .padding(.bottom, 2)
            } else {
                VStack(spacing: 8) {
                    // Display any images attached to the assistant message
                    if message.hasImages, let images = message.imageData {
                        ForEach(Array(images.enumerated()), id: \.offset) { _, data in
                            if let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: 250, maxHeight: 250)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }

                    // Extract and display any base64 images from markdown content
                    let extracted = Self.extractBase64Images(from: message.content)
                    ForEach(Array(extracted.images.enumerated()), id: \.offset) { _, data in
                        if let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 250, maxHeight: 250)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }

                    if !extracted.text.isEmpty {
                        HStack(alignment: .bottom, spacing: 0) {
                            Markdown(extracted.text)
                                .markdownTheme(.openClaw)
                                .textSelection(.enabled)

                            if message.isStreaming {
                                streamingCursor
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else if message.isStreaming {
                        streamingCursor
                    }
                }
            }
        }
    }

    // MARK: - Base64 Image Extraction

    struct ExtractedContent {
        let text: String
        let images: [Data]
    }

    static func extractBase64Images(from content: String) -> ExtractedContent {
        // Match markdown images with base64 data URIs: ![...](data:image/...;base64,...)
        let pattern = #"!\[[^\]]*\]\(data:image/[^;]+;base64,([A-Za-z0-9+/=\s]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return ExtractedContent(text: content, images: [])
        }

        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, options: [], range: range)

        guard !matches.isEmpty else {
            return ExtractedContent(text: content, images: [])
        }

        var images: [Data] = []
        var cleanedText = content

        // Process matches in reverse to preserve indices
        for match in matches.reversed() {
            if match.numberOfRanges > 1,
               let base64Range = Range(match.range(at: 1), in: content) {
                let base64String = String(content[base64Range]).replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
                if let data = Data(base64Encoded: base64String) {
                    images.insert(data, at: 0)
                }
            }
            if let fullRange = Range(match.range, in: cleanedText) {
                cleanedText.removeSubrange(fullRange)
            }
        }

        return ExtractedContent(
            text: cleanedText.trimmingCharacters(in: .whitespacesAndNewlines),
            images: images
        )
    }

    private var bubbleBackground: some ShapeStyle {
        if isUser {
            return AnyShapeStyle(Color.openClawRed)
        } else {
            return AnyShapeStyle(Color(.systemGray6))
        }
    }

    private var streamingCursor: some View {
        Text("|")
            .font(.body)
            .foregroundStyle(Color.openClawRed)
            .opacity(0.8)
            .modifier(BlinkingModifier())
    }
}

private struct BlinkingModifier: ViewModifier {
    @State private var visible = true

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: visible)
            .onAppear { visible = false }
    }
}

struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 8, height: 8)
                    .offset(y: animating ? -6 : 0)
                    .animation(
                        .easeInOut(duration: 0.4)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}
