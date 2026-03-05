import SwiftUI

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    var settingsStore: SettingsStore
    @State private var showSettings = false
    @State private var textInput = ""
    @State private var showTextInput = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageList
                Divider()
                inputArea
            }
            .navigationTitle("OpenClaw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    lobsterIcon
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                            .foregroundStyle(.openClawRed)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(store: settingsStore)
            }
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    if viewModel.messages.isEmpty {
                        emptyState
                    }

                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel.messages.last?.content) {
                // Auto-scroll as new content streams in
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
        VStack(spacing: 12) {
            // Error banner
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // State indicator
            if viewModel.state != .idle {
                stateIndicator
                    .transition(.opacity)
            }

            HStack(spacing: 16) {
                // Text input toggle
                Button(action: { withAnimation { showTextInput.toggle() } }) {
                    Image(systemName: showTextInput ? "mic.fill" : "keyboard")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                if showTextInput {
                    textInputField
                } else {
                    Spacer()
                    TalkButton(
                        state: viewModel.state,
                        audioLevel: viewModel.audioLevel,
                        onPress: { viewModel.startRecording() },
                        onRelease: { viewModel.stopRecordingAndSend() }
                    )
                    Spacer()
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .background(.ultraThinMaterial)
        .animation(.easeInOut(duration: 0.2), value: viewModel.state)
        .animation(.easeInOut(duration: 0.2), value: viewModel.errorMessage != nil)
    }

    private var textInputField: some View {
        HStack(spacing: 10) {
            TextField("Message...", text: $textInput, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            Button(action: {
                viewModel.sendText(textInput)
                textInput = ""
            }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
                    .foregroundStyle(.openClawRed)
            }
            .disabled(textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.state != .idle)
        }
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
                    .scaleEffect(0.7)
                Text("Transcribing...")
            case .thinking:
                ProgressView()
                    .scaleEffect(0.7)
                Text("Thinking...")
            case .streaming:
                Image(systemName: "text.word.spacing")
                    .foregroundStyle(.openClawRed)
                Text("Responding...")
            case .speaking:
                Image(systemName: "speaker.wave.2")
                    .foregroundStyle(.openClawRed)
                    .symbolEffect(.pulse)
                Text("Speaking...")
            case .idle:
                EmptyView()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
                .frame(height: 80)

            Text("🦞")
                .font(.system(size: 64))

            Text("OpenClaw Chat")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Hold the mic button to talk to your agent,\nor tap the keyboard icon to type.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var lobsterIcon: some View {
        Text("🦞")
            .font(.title2)
    }
}
