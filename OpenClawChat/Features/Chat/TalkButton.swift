import SwiftUI

struct TalkButton: View {
    let state: ChatState
    let audioLevel: Float
    let onPress: () -> Void
    let onRelease: () -> Void

    @State private var isPressed = false

    private var size: CGFloat { 72 }

    var body: some View {
        ZStack {
            // Outer pulsing ring (while recording)
            if state == .recording {
                Circle()
                    .stroke(Color.openClawRed.opacity(0.3), lineWidth: 3)
                    .frame(width: size + 20 + CGFloat(audioLevel * 60),
                           height: size + 20 + CGFloat(audioLevel * 60))
                    .animation(.easeOut(duration: 0.1), value: audioLevel)
            }

            // Processing spinner ring
            if state == .transcribing || state == .thinking {
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(Color.openClawRed, lineWidth: 3)
                    .frame(width: size + 12, height: size + 12)
                    .rotationEffect(.degrees(state == .thinking ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: state)
            }

            // Main button
            Circle()
                .fill(buttonColor)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.2), radius: isPressed ? 2 : 6, y: isPressed ? 1 : 3)
                .scaleEffect(isPressed ? 0.92 : 1.0)

            // Icon
            buttonIcon
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed && canStartRecording {
                        isPressed = true
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onPress()
                    }
                }
                .onEnded { _ in
                    if isPressed {
                        isPressed = false
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onRelease()
                    }
                }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .accessibilityLabel(accessibilityLabel)
    }

    private var canStartRecording: Bool {
        state == .idle
    }

    private var buttonColor: Color {
        switch state {
        case .recording: return .red
        case .transcribing, .thinking: return .openClawRed.opacity(0.6)
        case .streaming, .speaking: return .openClawRed.opacity(0.4)
        case .idle: return .openClawRed
        }
    }

    @ViewBuilder
    private var buttonIcon: some View {
        switch state {
        case .idle:
            Image(systemName: "mic.fill")
        case .recording:
            Image(systemName: "mic.fill")
                .symbolEffect(.pulse)
        case .transcribing:
            Image(systemName: "waveform")
        case .thinking:
            Image(systemName: "brain")
        case .streaming, .speaking:
            Image(systemName: "speaker.wave.2.fill")
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle: return "Hold to talk"
        case .recording: return "Recording. Release to send."
        case .transcribing: return "Transcribing your message"
        case .thinking: return "Waiting for response"
        case .streaming: return "Receiving response"
        case .speaking: return "Playing response. Tap to stop."
        }
    }
}
