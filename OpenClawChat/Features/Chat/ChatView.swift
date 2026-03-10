import SwiftUI
import PhotosUI

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    var settingsStore: SettingsStore
    var onBack: (() -> Void)?
    var onDeleteChannel: (() -> Void)?
    @State private var textInput = ""
    @State private var showTextInput = true
    @State private var showClearConfirm = false
    @State private var showDeleteConfirm = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var attachedImages: [Data] = []

    var body: some View {
        VStack(spacing: 0) {
            // Custom nav bar
            navBar
            Divider().opacity(0.3)

            // Chat area
            messageList

            // Input area
            Divider().opacity(0.3)
            inputArea
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Navigation Bar

    private var navBar: some View {
        ZStack {
            // Centered title
            Text(viewModel.channel.name)
                .font(.headline)
                .fontWeight(.semibold)

            // Left/right buttons
            HStack {
                Button(action: { onBack?() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Channels")
                    }
                    .font(.body)
                    .foregroundStyle(.openClawRed)
                }

                Spacer()

                HStack(spacing: 14) {
                    Menu {
                        Button(action: { showClearConfirm = true }) {
                            Label("Clear Chat", systemImage: "trash")
                        }
                        Button(role: .destructive, action: { showDeleteConfirm = true }) {
                            Label("Delete Channel", systemImage: "minus.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.body)
                            .foregroundStyle(.openClawRed)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .alert("Clear chat history?", isPresented: $showClearConfirm) {
            Button("Clear Chat", role: .destructive) {
                viewModel.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all messages in this channel. This cannot be undone.")
        }
        .alert("Delete this channel?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                onDeleteChannel?()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete the channel and all its messages. This cannot be undone.")
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    if viewModel.messages.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .containerRelativeFrame(.vertical)
                    }

                    ForEach(viewModel.messages) { message in
                        MessageBubble(
                            message: message,
                            showTokenUsage: settingsStore.settings.showTokenUsage,
                            onRetry: message.hasFailed ? { viewModel.retryMessage(id: message.id) } : nil,
                            onDelete: { viewModel.deleteMessage(id: message.id) }
                        )
                        .id(message.id)
                    }
                }
                .padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.last?.content) {
                if let lastID = viewModel.messages.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Input Area

    private var inputArea: some View {
        VStack(spacing: 0) {
            // Error banner
            if let error = viewModel.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if viewModel.isConversationMode {
                // Conversation mode UI
                conversationModeArea
            } else if showTextInput {
                // Text mode: compact bar with text field + mic switch
                // State indicator inline
                if viewModel.state != .idle {
                    stateIndicator
                        .padding(.top, 10)
                        .transition(.opacity)
                }

                // Attached image previews
                if !attachedImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(attachedImages.enumerated()), id: \.offset) { index, data in
                                if let uiImage = UIImage(data: data) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        .overlay(alignment: .topTrailing) {
                                            Button(action: { attachedImages.remove(at: index) }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 18))
                                                    .symbolRenderingMode(.palette)
                                                    .foregroundStyle(.white, .black.opacity(0.6))
                                            }
                                            .offset(x: 6, y: -6)
                                        }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                    }
                    .padding(.top, 4)
                }

                HStack(spacing: 10) {
                    PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 8, matching: .images) {
                        Image(systemName: "photo")
                            .font(.title3)
                            .foregroundStyle(.openClawRed)
                    }
                    .onChange(of: selectedPhotos) {
                        Task { await loadSelectedPhotos() }
                    }

                    TextField("Message...", text: $textInput, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    if textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachedImages.isEmpty {
                        // Mic button to switch to voice mode
                        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showTextInput = false } }) {
                            Image(systemName: "mic.fill")
                                .font(.body)
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(Color.openClawRed)
                                .clipShape(Circle())
                        }
                    } else {
                        // Send button
                        Button(action: {
                            if settingsStore.settings.hapticsEnabled {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                            viewModel.sendText(textInput, images: attachedImages)
                            textInput = ""
                            attachedImages = []
                            selectedPhotos = []
                        }) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title)
                                .foregroundStyle(.openClawRed)
                        }
                        .disabled(viewModel.state != .idle)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            } else {
                // Voice mode: mic centered, keyboard to the right
                VStack(spacing: 8) {
                    // State indicator
                    if viewModel.state != .idle {
                        stateIndicator
                            .padding(.top, 8)
                            .transition(.opacity)
                    }

                    TalkButton(
                        state: viewModel.state,
                        audioLevel: viewModel.audioLevel,
                        hapticsEnabled: settingsStore.settings.hapticsEnabled,
                        onTap: { viewModel.enterConversationMode() },
                        onHoldStart: { viewModel.startRecording() },
                        onHoldEnd: { viewModel.stopRecordingAndSend() }
                    )
                    .overlay(alignment: .trailing) {
                        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showTextInput = true } }) {
                            Image(systemName: "keyboard")
                                .font(.title2)
                                .foregroundStyle(.openClawRed)
                        }
                        .offset(x: 56)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
        }
        .background(Color(.secondarySystemBackground))
        .animation(.easeInOut(duration: 0.2), value: viewModel.state)
        .animation(.easeInOut(duration: 0.2), value: viewModel.errorMessage != nil)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isConversationMode)
    }

    // MARK: - Conversation Mode

    private var conversationModeArea: some View {
        VStack(spacing: 16) {
            // State indicator (always shown in conversation mode)
            conversationStateIndicator
                .padding(.top, 12)

            // Pulsing audio visualization
            ConversationPulse(
                audioLevel: viewModel.audioLevel,
                state: viewModel.state
            )

            // End button
            Button(action: { viewModel.exitConversationMode() }) {
                Text("End")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 80, height: 44)
                    .background(Color.red)
                    .clipShape(Capsule())
            }
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private var conversationStateIndicator: some View {
        HStack(spacing: 8) {
            switch viewModel.state {
            case .recording:
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Text("Listening...")
            case .transcribing:
                ProgressView()
                    .scaleEffect(0.8)
                Text("Processing...")
            case .thinking:
                ProgressView()
                    .scaleEffect(0.8)
                Text("Thinking...")
            case .streaming:
                Circle()
                    .fill(.openClawRed)
                    .frame(width: 8, height: 8)
                    .modifier(PulsingModifier())
                Text("Responding...")
            case .speaking:
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.openClawRed)
                    .symbolEffect(.variableColor.iterative)
                Text("Speaking...")
                Button(action: { viewModel.stopSpeaking() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            case .idle:
                Text("Conversation Mode")
            }
        }
        .font(.subheadline)
        .fontWeight(.medium)
        .foregroundStyle(.secondary)
    }

    // MARK: - State Indicator

    private var stateIndicator: some View {
        HStack(spacing: 8) {
            switch viewModel.state {
            case .recording:
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Text("Listening...")
            case .transcribing:
                ProgressView()
                    .scaleEffect(0.8)
                Text("Transcribing...")
            case .thinking:
                ProgressView()
                    .scaleEffect(0.8)
                Text("Thinking...")
            case .streaming:
                Circle()
                    .fill(.openClawRed)
                    .frame(width: 8, height: 8)
                    .modifier(PulsingModifier())
                Text("Responding...")
            case .speaking:
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.openClawRed)
                    .symbolEffect(.variableColor.iterative)
                Text("Speaking...")
                Button(action: { viewModel.stopSpeaking() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            case .idle:
                EmptyView()
            }
        }
        .font(.subheadline)
        .fontWeight(.medium)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(.systemGray5).opacity(0.8))
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.openClawRed.opacity(0.5))

            Text("ClawTalk")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            Text("Type a message, or tap the\nmic to use voice input.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Photo Loading

    private func loadSelectedPhotos() async {
        var newImages: [Data] = []
        for item in selectedPhotos {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                let resized = uiImage.resizedToFit(maxDimension: 512)
                if let jpeg = resized.jpegData(compressionQuality: 0.4) {
                    newImages.append(jpeg)
                }
            }
        }
        attachedImages = newImages
    }
}

// MARK: - Conversation Pulse Animation

private struct ConversationPulse: View {
    let audioLevel: Float
    let state: ChatState

    var body: some View {
        ZStack {
            // Outer ring reacts to audio
            Circle()
                .stroke(ringColor.opacity(0.2), lineWidth: 2)
                .frame(width: 80 + CGFloat(audioLevel * 40),
                       height: 80 + CGFloat(audioLevel * 40))
                .animation(.easeOut(duration: 0.1), value: audioLevel)

            // Middle ring
            Circle()
                .stroke(ringColor.opacity(0.4), lineWidth: 1.5)
                .frame(width: 60 + CGFloat(audioLevel * 20),
                       height: 60 + CGFloat(audioLevel * 20))
                .animation(.easeOut(duration: 0.1), value: audioLevel)

            // Center circle
            Circle()
                .fill(centerColor)
                .frame(width: 44, height: 44)

            // Center icon
            centerIcon
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(height: 100)
    }

    private var ringColor: Color {
        switch state {
        case .recording: return .openClawRed
        case .speaking: return .blue
        default: return .openClawRed.opacity(0.5)
        }
    }

    private var centerColor: Color {
        switch state {
        case .recording: return .openClawRed
        case .speaking: return .blue
        case .transcribing, .thinking, .streaming: return .openClawRed.opacity(0.6)
        case .idle: return .openClawRed
        }
    }

    @ViewBuilder
    private var centerIcon: some View {
        switch state {
        case .recording:
            Image(systemName: "mic.fill")
        case .speaking:
            Image(systemName: "speaker.wave.2.fill")
                .symbolEffect(.variableColor.iterative)
        case .transcribing, .thinking:
            ProgressView()
                .tint(.white)
                .scaleEffect(0.8)
        case .streaming:
            Image(systemName: "waveform")
        case .idle:
            Image(systemName: "mic.fill")
        }
    }
}

private struct PulsingModifier: ViewModifier {
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pulsing ? 1.4 : 1.0)
            .opacity(pulsing ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
    }
}

// MARK: - Model Picker Sheet

extension UIImage {
    func resizedToFit(maxDimension: CGFloat) -> UIImage {
        let ratio = min(maxDimension / size.width, maxDimension / size.height)
        guard ratio < 1 else { return self }
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
