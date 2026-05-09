import SwiftUI

/// Compact mic button for the chat input bar. Tap to toggle recording, or
/// press-and-hold to do push-to-talk. Mirrors the gesture model of the
/// larger TalkButton without the audio-level ring.
struct InlineMicButton: View {
    let state: ChatState
    let hapticsEnabled: Bool
    let onTap: () -> Void
    let onHoldStart: () -> Void
    let onHoldEnd: () -> Void

    @State private var isPressed = false
    @State private var holdTimer: Task<Void, Never>?
    @State private var isHolding = false

    private let size: CGFloat = 40
    private let holdThreshold: UInt64 = 300_000_000  // 0.3s

    var body: some View {
        ZStack {
            Circle()
                .fill(buttonColor)
                .frame(width: size, height: size)
                .scaleEffect(isPressed ? 0.92 : 1.0)
            icon
                .font(.body)
                .foregroundStyle(.white)
        }
        .frame(width: size + 12, height: size + 12)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed, canInteract else { return }
                    if state == .recording {
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
                .onEnded { _ in
                    holdTimer?.cancel()
                    holdTimer = nil
                    guard isPressed else { return }
                    isPressed = false
                    if hapticsEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                    if isHolding {
                        onHoldEnd()
                    } else {
                        onTap()
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
        case .idle: return .openClawRed
        case .transcribing, .thinking: return .openClawRed.opacity(0.5)
        case .streaming, .speaking: return .openClawRed.opacity(0.35)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch state {
        case .recording:
            Image(systemName: "mic.fill").symbolEffect(.pulse)
        case .transcribing:
            Image(systemName: "waveform")
        case .thinking:
            Image(systemName: "ellipsis")
        case .streaming, .speaking:
            Image(systemName: "speaker.wave.2.fill")
        case .idle:
            Image(systemName: "mic.fill")
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle: return "Tap to record, or hold to talk"
        case .recording: return "Recording. Tap or release to send."
        case .transcribing: return "Transcribing"
        case .thinking: return "Waiting for response"
        case .streaming: return "Receiving response"
        case .speaking: return "Playing response"
        }
    }
}
