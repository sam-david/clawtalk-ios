import SwiftUI
import MarkdownUI

struct MessageBubble: View {
    let message: Message
    let onReplayAudio: (() -> Void)?

    init(message: Message, onReplayAudio: (() -> Void)? = nil) {
        self.message = message
        self.onReplayAudio = onReplayAudio
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
                }
            }

            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var bubbleContent: some View {
        if isUser {
            Text(message.content)
                .font(.body)
                .foregroundStyle(.white)
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
