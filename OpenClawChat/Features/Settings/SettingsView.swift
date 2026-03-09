import SwiftUI

struct SettingsView: View {
    @Bindable var store: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                connectionSection
                displaySection
                voiceSection
                ttsSection
                sttSection
                dataSection
                securitySection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                            store.save()
                            dismiss()
                        }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Connection

    private var connectionSection: some View {
        Section {
            TextField("Gateway URL", text: $store.settings.gatewayURL)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            SecureField("Gateway Token", text: $store.gatewayToken)
                .textContentType(.password)

            Picker("API Mode", selection: $store.settings.agentAPIMode) {
                ForEach(AgentAPIMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            Toggle("WebSocket Mode", isOn: $store.settings.useWebSocket)

            if store.settings.useWebSocket {
                HStack {
                    Text("WebSocket Port")
                    Spacer()
                    TextField("18789", text: Binding(
                        get: { String(store.settings.webSocketPort) },
                        set: { store.settings.webSocketPort = Int($0) ?? 18789 }
                    ))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
            }
        } header: {
            Text("OpenClaw Gateway")
        } footer: {
            if store.settings.useWebSocket {
                Text("WebSocket mode connects to port 18789 for real-time streaming with full session management. The agent remembers context, can use tools, and writes to memory.")
            } else {
                switch store.settings.agentAPIMode {
                case .chatCompletions:
                    Text("Standard Chat Completions API. Works with all gateways.")
                case .openResponses:
                    Text("Open Responses API provides token usage data. Requires gateway support (endpoints.responses.enabled).")
                }
            }
        }
    }

    // MARK: - Display

    private var displaySection: some View {
        Section {
            Toggle("Show Token Usage", isOn: $store.settings.showTokenUsage)
        } header: {
            Text("Display")
        } footer: {
            Text("Show input/output token counts under assistant messages. Requires Open Responses API mode.")
        }
    }

    // MARK: - Voice Toggle

    private var voiceSection: some View {
        Section {
            Toggle("Voice Input (STT)", isOn: $store.settings.voiceInputEnabled)
            Toggle("Voice Output (TTS)", isOn: $store.settings.voiceOutputEnabled)
            Toggle("Haptic Feedback", isOn: $store.settings.hapticsEnabled)
        } header: {
            Text("Voice")
        } footer: {
            Text("Disable voice for text-only chat. Voice input uses on-device transcription. Haptics provide tactile feedback on the talk button and message events.")
        }
    }

    // MARK: - TTS Provider

    private var ttsSection: some View {
        Section {
            Picker("Provider", selection: $store.settings.ttsProvider) {
                ForEach(TTSProvider.allCases) { provider in
                    Text(provider.rawValue).tag(provider)
                }
            }

            switch store.settings.ttsProvider {
            case .elevenlabs:
                SecureField("API Key", text: $store.elevenLabsAPIKey)
                    .textContentType(.password)
                TextField("Voice ID", text: $store.settings.elevenLabsVoiceID)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            case .openai:
                SecureField("API Key", text: $store.openAIAPIKey)
                    .textContentType(.password)
                Picker("Voice", selection: $store.settings.openAIVoice) {
                    Text("Alloy").tag("alloy")
                    Text("Echo").tag("echo")
                    Text("Fable").tag("fable")
                    Text("Onyx").tag("onyx")
                    Text("Nova").tag("nova")
                    Text("Shimmer").tag("shimmer")
                }
            case .apple:
                EmptyView()
            }
        } header: {
            Text("Text-to-Speech")
        } footer: {
            switch store.settings.ttsProvider {
            case .elevenlabs:
                Text("ElevenLabs provides the most natural voices. Free tier: 10,000 chars/month.")
            case .openai:
                Text("OpenAI TTS is cost-effective with good quality.")
            case .apple:
                Text("Apple's built-in voice. Free and works offline, but less natural.")
            }
        }
    }

    // MARK: - STT Model

    @State private var pendingModelSize: WhisperModelSize?
    @State private var showModelConfirm = false

    private var sttSection: some View {
        Section {
            Picker("Whisper Model", selection: Binding(
                get: { store.settings.whisperModelSize },
                set: { newSize in
                    if newSize == .largeTurbo && store.settings.whisperModelSize != .largeTurbo {
                        pendingModelSize = newSize
                        showModelConfirm = true
                    } else {
                        store.settings.whisperModelSize = newSize
                    }
                }
            )) {
                ForEach(WhisperModelSize.allCases) { model in
                    Text(model.displayName).tag(model)
                }
            }
            .confirmationDialog("Download Large Model?", isPresented: $showModelConfirm, titleVisibility: .visible) {
                Button("Download (~1.6 GB)") {
                    if let size = pendingModelSize {
                        store.settings.whisperModelSize = size
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The Large Turbo model provides the best accuracy but requires ~1.6 GB of storage. It will download on next voice input.")
            }
        } header: {
            Text("Speech-to-Text")
        } footer: {
            Text("Runs entirely on-device. Audio never leaves your phone.")
        }
    }

    // MARK: - Security Info

    // MARK: - Data

    @State private var showClearConfirm = false

    private var dataSection: some View {
        Section {
            Button("Clear Chat History", role: .destructive) {
                showClearConfirm = true
            }
            .confirmationDialog("Clear all chat history?", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("Clear History", role: .destructive) {
                    ConversationStore.shared.clearAll()
                }
            } message: {
                Text("This cannot be undone.")
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Chat history is stored locally on this device with iOS Data Protection (encrypted at rest).")
        }
    }

    // MARK: - Security Info

    private var securitySection: some View {
        Section {
            LabeledContent("Token Storage", value: "iOS Keychain")
            LabeledContent("Transport", value: store.settings.useWebSocket ? "WSS + HTTPS" : "HTTPS Only")
            LabeledContent("STT Processing", value: "On-Device")
        } header: {
            Text("Security")
        } footer: {
            Text("API keys and tokens are stored in the iOS Keychain, encrypted at rest. Voice is transcribed on-device — audio never leaves your phone. Agent communication uses HTTPS.")
        }
    }
}
