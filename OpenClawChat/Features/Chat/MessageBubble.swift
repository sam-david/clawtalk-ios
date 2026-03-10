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

                        if !isUser, let model = message.modelName {
                            Text("· \(model)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        if !isUser, showTokenUsage, let usage = message.tokenUsage {
                            Text("· \(usage.outputTokens) tokens")
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
            VStack(alignment: .trailing, spacing: 8) {
                if message.hasImages, let images = message.imageData {
                    ForEach(Array(images.enumerated()), id: \.offset) { _, data in
                        if let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 200, maxHeight: 200)
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
                    .padding(.vertical, 4)
            } else {
                HStack(alignment: .bottom, spacing: 0) {
                    Markdown(message.content)
                        .markdownTheme(.openClaw)
                        .textSelection(.enabled)

                    if message.isStreaming {
                        streamingCursor
                    }
                }
            }
        }
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
