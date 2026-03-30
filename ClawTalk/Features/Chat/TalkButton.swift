import SwiftUI

struct TalkButton: View {
    let state: ChatState
    let audioLevel: Float
    let hapticsEnabled: Bool
    let onTap: () -> Void
    let onHoldStart: () -> Void
    let onHoldEnd: () -> Void

    @State private var isPressed = false
    @State private var holdTimer: Task<Void, Never>?
    @State private var isHolding = false

    private let size: CGFloat = 76
    /// Duration (in seconds) a press must be held to count as push-to-talk
    private let holdThreshold: UInt64 = 300_000_000 // 0.3s

    var body: some View {
        ZStack {
            // Outer pulsing ring (while recording)
            if state == .recording {
                Circle()
                    .stroke(Color.openClawRed.opacity(0.25), lineWidth: 2.5)
                    .frame(width: size + 16 + CGFloat(audioLevel * 50),
                           height: size + 16 + CGFloat(audioLevel * 50))
                    .animation(.easeOut(duration: 0.08), value: audioLevel)
            }

            // Processing spinner ring
            if state == .transcribing || state == .thinking {
                Circle()
                    .trim(from: 0, to: 0.65)
                    .stroke(Color.openClawRed.opacity(0.6), lineWidth: 2.5)
                    .frame(width: size + 10, height: size + 10)
                    .rotationEffect(.degrees(state == .thinking ? 360 : 0))
                    .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: state)
            }

            // Main button
            Circle()
                .fill(buttonColor)
                .frame(width: size, height: size)
                .shadow(color: buttonColor.opacity(0.4), radius: isPressed ? 4 : 8, y: isPressed ? 1 : 3)
                .scaleEffect(isPressed ? 0.9 : 1.0)

            // Icon
            buttonIcon
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(width: size + 50, height: size + 50) // Stable hit area
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed && canInteract {
                        if state == .recording {
                            // Tap while recording — stop on release
                            isPressed = true
                            isHolding = false
                        } else {
                            isPressed = true
                            isHolding = false
                            if hapticsEnabled { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }

                            holdTimer = Task { @MainActor in
                                try? await Task.sleep(nanoseconds: holdThreshold)
                                guard !Task.isCancelled else { return }
                                isHolding = true
                                if hapticsEnabled { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
                                onHoldStart()
                            }
                        }
                    }
                }
                .onEnded { _ in
                    holdTimer?.cancel()
                    holdTimer = nil
                    if isPressed {
                        isPressed = false
                        if isHolding {
                            if hapticsEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                            onHoldEnd()
                        } else {
                            if hapticsEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                            onTap()
                        }
                    }
                }
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.65), value: isPressed)
        .accessibilityLabel(accessibilityLabel)
    }

    private var canInteract: Bool {
        state == .idle || state == .recording
    }

    private var buttonColor: Color {
        switch state {
        case .recording: return .red
        case .transcribing, .thinking: return .openClawRed.opacity(0.5)
        case .streaming, .speaking: return .openClawRed.opacity(0.35)
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
            Image(systemName: "ellipsis")
        case .streaming, .speaking:
            Image(systemName: "speaker.wave.2.fill")
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle: return "Tap or hold to record a voice message."
        case .recording: return "Recording. Tap or release to send."
        case .transcribing: return "Transcribing your message"
        case .thinking: return "Waiting for response"
        case .streaming: return "Receiving response"
        case .speaking: return "Playing response. Tap to stop."
        }
    }
}
