import SwiftUI

struct SettingsView: View {
    @Bindable var store: SettingsStore
    var gatewayConnection: GatewayConnection
    @Environment(\.dismiss) private var dismiss

    @State private var connectionTestState: ConnectionTestState = .idle
    @State private var elevenLabsVoices: [ElevenLabsVoice] = []
    @State private var voicesFetchState: FetchState = .idle
    @State private var previewService: (any SpeechService)?
    @State private var previewPlayback: AudioPlaybackManager?
    @State private var isPreviewing = false

    enum ConnectionTestState: Equatable {
        case idle
        case testing
        case success
        case failed(String)
    }

    enum FetchState: Equatable {
        case idle
        case loading
        case loaded
        case loadedDefaults
    }

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
                .onChange(of: store.settings.useWebSocket) { _, newValue in
                    if newValue {
                        // Auto-connect when toggled on
                        if store.isConfigured {
                            store.save()
                            Task {
                                await gatewayConnection.connect(
                                    resolvedURL: store.settings.resolvedWebSocketURL,
                                    token: store.gatewayToken
                                )
                            }
                        }
                    } else {
                        // Disconnect when toggled off
                        Task {
                            await gatewayConnection.disconnect()
                        }
                    }
                }

            if store.settings.useWebSocket {
                HStack {
                    Text("WS Port or Path")
                    Spacer()
                    TextField("/ws", text: $store.settings.webSocketPath)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                }
            }

            if store.settings.useWebSocket {
                // Live WebSocket connection status
                HStack {
                    Text("Connection")
                    Spacer()
                    switch gatewayConnection.connectionState {
                    case .connected:
                        HStack(spacing: 6) {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                            Text("Connected")
                                .font(.subheadline)
                                .foregroundStyle(.green)
                        }
                    case .connecting:
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Connecting...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    case .disconnected:
                        HStack(spacing: 6) {
                            Circle()
                                .fill(.red)
                                .frame(width: 8, height: 8)
                            Text("Disconnected")
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                    }
                }

                if gatewayConnection.connectionState == .disconnected {
                    if let error = gatewayConnection.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button("Reconnect") {
                        store.save()
                        Task {
                            await gatewayConnection.connect(
                                resolvedURL: store.settings.resolvedWebSocketURL,
                                token: store.gatewayToken
                            )
                        }
                    }
                    .disabled(store.settings.gatewayURL.isEmpty || store.gatewayToken.isEmpty)
                }
            } else {
                // HTTP connection test
                Button(action: { testConnection() }) {
                    HStack {
                        Text("Test Connection")
                        Spacer()
                        switch connectionTestState {
                        case .idle:
                            EmptyView()
                        case .testing:
                            ProgressView()
                                .scaleEffect(0.8)
                        case .success:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .failed:
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
                .disabled(store.settings.gatewayURL.isEmpty || store.gatewayToken.isEmpty || connectionTestState == .testing)

                if case .failed(let error) = connectionTestState {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text("OpenClaw Gateway")
        } footer: {
            if store.settings.useWebSocket {
                Text("WebSocket enables real-time streaming. Enter a path (e.g. /ws) for tunneled gateways or a port (e.g. 18789) for local connections.")
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
            Text("Show input/output token counts under assistant messages.")
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
                    .onChange(of: store.elevenLabsAPIKey) { oldValue, newValue in
                        guard oldValue != newValue else { return }
                        // Reset voices when key changes so user re-fetches
                        elevenLabsVoices = []
                        voicesFetchState = .idle
                    }

                if elevenLabsVoices.isEmpty {
                    Button(action: { fetchElevenLabsVoices() }) {
                        HStack {
                            Text("Load Voices")
                            Spacer()
                            if voicesFetchState == .loading {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                    }
                    .disabled(store.elevenLabsAPIKey.isEmpty || voicesFetchState == .loading)
                } else {
                    Picker("Voice", selection: $store.settings.elevenLabsVoiceID) {
                        ForEach(elevenLabsVoices) { voice in
                            Text(voice.name).tag(voice.voice_id)
                        }
                    }
                }

                if voicesFetchState == .loadedDefaults {
                    Text("Showing default voices. Enable \"voices_read\" on your API key to see all voices including custom ones.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                voicePreviewButton
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

                voicePreviewButton
            case .apple:
                voicePreviewButton
            }
        } header: {
            Text("Text-to-Speech")
        } footer: {
            switch store.settings.ttsProvider {
            case .elevenlabs:
                Text("ElevenLabs provides the most natural voices.\nFree tier: 10,000 chars/month.")
            case .openai:
                Text("OpenAI TTS is cost-effective with good quality.")
            case .apple:
                Text("Apple's built-in voice. Free and works offline, but less natural.")
            }
        }
        .onAppear {
            if store.settings.ttsProvider == .elevenlabs && !store.elevenLabsAPIKey.isEmpty && elevenLabsVoices.isEmpty {
                fetchElevenLabsVoices()
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

    // MARK: - Connection Test

    private func testConnection() {
        // Save current values before testing
        store.save()
        connectionTestState = .testing

        Task {
            do {
                let baseURL = store.settings.gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
                    connectionTestState = .failed("Invalid gateway URL")
                    return
                }

                // POST with empty messages — validates auth without triggering a real response.
                // Valid token → 400 (bad request), invalid token → 401.
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(store.gatewayToken)", forHTTPHeaderField: "Authorization")
                request.httpBody = Data("{\"model\":\"openclaw:main\",\"messages\":[],\"stream\":false}".utf8)
                request.timeoutInterval = 15

                let (_, response) = try await URLSession.shared.data(for: request)

                if let http = response as? HTTPURLResponse {
                    switch http.statusCode {
                    case 200...299, 400:
                        // 400 = auth passed, just invalid request body (empty messages)
                        connectionTestState = .success
                    case 401, 403:
                        connectionTestState = .failed("Authentication failed (HTTP \(http.statusCode)). Check your gateway token.")
                    default:
                        connectionTestState = .failed("Gateway returned HTTP \(http.statusCode)")
                    }
                } else {
                    connectionTestState = .failed("Unexpected response")
                }
            } catch let error as URLError {
                switch error.code {
                case .notConnectedToInternet:
                    connectionTestState = .failed("No internet connection")
                case .timedOut:
                    connectionTestState = .failed("Connection timed out. Check the URL and ensure the gateway is running.")
                case .cannotFindHost, .cannotConnectToHost:
                    connectionTestState = .failed("Cannot reach gateway. Check the URL.")
                case .secureConnectionFailed:
                    connectionTestState = .failed("SSL/TLS connection failed. Make sure the gateway uses HTTPS.")
                default:
                    connectionTestState = .failed(error.localizedDescription)
                }
            } catch {
                connectionTestState = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - ElevenLabs Voices

    private func voiceLabel(for id: String) -> String {
        if let voice = elevenLabsVoices.first(where: { $0.voice_id == id }) {
            return voice.name
        }
        return id.isEmpty ? "Select a voice" : "Voice (\(id.prefix(8))...)"
    }

    private func fetchElevenLabsVoices() {
        let apiKey = store.elevenLabsAPIKey
        guard !apiKey.isEmpty else { return }
        voicesFetchState = .loading
        Task {
            let result = await ElevenLabsVoice.fetchAll(apiKey: apiKey)
            elevenLabsVoices = result.voices
            voicesFetchState = result.usedAPI ? .loaded : .loadedDefaults
        }
    }

    // MARK: - Voice Preview

    private var voicePreviewButton: some View {
        Button(action: { isPreviewing ? stopPreview() : startPreview() }) {
            HStack {
                Text(isPreviewing ? "Stop Preview" : "Preview Voice")
                Spacer()
                if isPreviewing {
                    Image(systemName: "stop.circle.fill")
                        .foregroundStyle(.openClawRed)
                } else {
                    Image(systemName: "play.circle.fill")
                        .foregroundStyle(.openClawRed)
                }
            }
        }
        .disabled(previewDisabled)
    }

    private var previewDisabled: Bool {
        switch store.settings.ttsProvider {
        case .elevenlabs:
            return store.elevenLabsAPIKey.isEmpty || store.settings.elevenLabsVoiceID.isEmpty
        case .openai:
            return store.openAIAPIKey.isEmpty
        case .apple:
            return false
        }
    }

    private func startPreview() {
        let sampleText = "Hello! This is a preview of your selected voice."

        let tts: any SpeechService
        switch store.settings.ttsProvider {
        case .elevenlabs:
            tts = ElevenLabsTTSService(voiceID: store.settings.elevenLabsVoiceID, apiKey: store.elevenLabsAPIKey)
        case .openai:
            tts = OpenAITTSService(voice: store.settings.openAIVoice, apiKey: store.openAIAPIKey)
        case .apple:
            tts = AppleTTSService()
        }

        previewService = tts
        isPreviewing = true

        if store.settings.ttsProvider == .apple {
            // Apple TTS plays directly via AVSpeechSynthesizer
            let _ = tts.streamSpeech(text: sampleText)
            // Auto-reset after a delay since Apple TTS doesn't give us completion
            Task {
                try? await Task.sleep(for: .seconds(4))
                if isPreviewing { isPreviewing = false }
            }
        } else {
            // ElevenLabs/OpenAI stream PCM through playback manager
            let playback = AudioPlaybackManager()
            previewPlayback = playback

            Task {
                do {
                    try playback.start()
                    let audioStream = tts.streamSpeech(text: sampleText)
                    for try await chunk in audioStream {
                        playback.enqueue(pcmData: chunk)
                    }
                    playback.markStreamingDone()
                    await playback.waitUntilFinished()
                } catch {
                    // Preview failed silently
                }
                playback.stop()
                isPreviewing = false
                previewPlayback = nil
            }
        }
    }

    private func stopPreview() {
        previewService?.stop()
        previewPlayback?.stop()
        previewPlayback = nil
        previewService = nil
        isPreviewing = false
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
