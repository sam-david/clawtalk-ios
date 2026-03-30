import SwiftUI

@main
struct ClawTalkApp: App {
    @State private var settingsStore: SettingsStore
    @State private var channelStore: ChannelStore
    @State private var selectedChannel: Channel?
    @State private var chatViewModel: ChatViewModel?
    @State private var showModelDownload = false
    @State private var modelManager = WhisperModelManager.shared
    @State private var cachedSTT: WhisperKitService?
    @State private var cachedSTTModelSize: WhisperModelSize?
    @State private var gatewayConnection = GatewayConnection()
    @State private var nodeConnection = NodeConnection()

    init() {
        #if DEBUG
        DemoDataSeeder.seedIfNeeded()
        #endif
        _settingsStore = State(initialValue: SettingsStore())
        _channelStore = State(initialValue: ChannelStore())
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !settingsStore.hasCompletedOnboarding {
                    OnboardingView(settingsStore: settingsStore) {
                        // Onboarding complete
                    }
                } else if showModelDownload {
                    ModelDownloadView(
                        modelSize: settingsStore.settings.whisperModelSize,
                        onComplete: {
                            showModelDownload = false
                        },
                        onSkip: {
                            showModelDownload = false
                        }
                    )
                } else if let vm = chatViewModel, selectedChannel != nil {
                    ChatView(viewModel: vm, settingsStore: settingsStore, gatewayConnection: gatewayConnection, onBack: goBack, onDeleteChannel: deleteCurrentChannel)
                } else {
                    ChannelListView(
                        channelStore: channelStore,
                        settingsStore: settingsStore,
                        gatewayConnection: gatewayConnection,
                        onSelect: { channel in
                            selectChannel(channel)
                        }
                    )
                    .onAppear {
                        if !modelManager.hasDownloadedModel && settingsStore.settings.voiceInputEnabled {
                            showModelDownload = true
                        }
                    }
                }
            }
            .overlay {
                ApprovalOverlayView(gatewayConnection: gatewayConnection)
            }
            .sheet(isPresented: Binding(
                get: { CanvasCapability.shared.isPresented },
                set: { CanvasCapability.shared.isPresented = $0 }
            )) {
                CanvasView(canvas: CanvasCapability.shared)
            }
            .tint(.openClawRed)
            .preferredColorScheme(.dark)
            .task {
                guard settingsStore.settings.useWebSocket,
                      settingsStore.isConfigured else { return }

                // Connect operator WebSocket
                if gatewayConnection.connectionState == .disconnected {
                    await gatewayConnection.connect(
                        resolvedURL: settingsStore.settings.resolvedWebSocketURL,
                        token: settingsStore.gatewayToken
                    )
                }

                // Connect node WebSocket
                if nodeConnection.connectionState == .disconnected {
                    await nodeConnection.connect(
                        resolvedURL: settingsStore.settings.resolvedWebSocketURL,
                        token: settingsStore.gatewayToken
                    )
                }
            }
            .onChange(of: settingsStore.settings.ttsProvider) {
                reconfigureServices()
            }
            .onChange(of: settingsStore.settings.voiceInputEnabled) {
                reconfigureServices()
            }
            .onChange(of: settingsStore.elevenLabsAPIKey) {
                reconfigureServices()
            }
            .onChange(of: settingsStore.openAIAPIKey) {
                reconfigureServices()
            }
        }
    }

    private func selectChannel(_ channel: Channel) {
        let vm = ChatViewModel(
            settings: settingsStore,
            channel: channel,
            channelStore: channelStore,
            gatewayConnection: gatewayConnection
        )
        configureServices(for: vm)
        chatViewModel = vm
        selectedChannel = channel

        // Wire node image injection to chat
        nodeConnection.onImagesReceived = { [weak vm] images, caption in
            vm?.injectImages(images, caption: caption)
        }

        // Auto-connect WebSocket if enabled, then load server history
        if settingsStore.settings.useWebSocket, settingsStore.isConfigured {
            Task {
                if gatewayConnection.connectionState == .disconnected {
                    await gatewayConnection.connect(
                        resolvedURL: settingsStore.settings.resolvedWebSocketURL,
                        token: settingsStore.gatewayToken
                    )
                }
                if nodeConnection.connectionState == .disconnected {
                    await nodeConnection.connect(
                        resolvedURL: settingsStore.settings.resolvedWebSocketURL,
                        token: settingsStore.gatewayToken
                    )
                }
                vm.loadServerHistory()
            }
        }
    }

    private func goBack() {
        chatViewModel?.stop()
        chatViewModel = nil
        selectedChannel = nil
        nodeConnection.onImagesReceived = nil
    }

    private func deleteCurrentChannel() {
        chatViewModel?.stop()
        if let channel = selectedChannel {
            channelStore.delete(channel)
        }
        chatViewModel = nil
        selectedChannel = nil
    }

    private func reconfigureServices() {
        guard let vm = chatViewModel else { return }
        configureServices(for: vm)
    }

    private func configureServices(for vm: ChatViewModel) {
        let secure = SecureStorage.shared
        let s = settingsStore.settings

        // STT — reuse cached instance if model size hasn't changed
        let stt: any TranscriptionService
        if let cached = cachedSTT, cachedSTTModelSize == s.whisperModelSize {
            stt = cached
        } else {
            let service = WhisperKitService(modelSize: s.whisperModelSize)
            cachedSTT = service
            cachedSTTModelSize = s.whisperModelSize
            stt = service
        }

        // TTS
        let tts: any SpeechService = {
            switch s.ttsProvider {
            case .elevenlabs:
                if let key = secure.elevenLabsAPIKey, !key.isEmpty {
                    return ElevenLabsTTSService(voiceID: s.elevenLabsVoiceID, apiKey: key)
                }
                return AppleTTSService()
            case .openai:
                if let key = secure.openAIAPIKey, !key.isEmpty {
                    return OpenAITTSService(voice: s.openAIVoice, apiKey: key)
                }
                return AppleTTSService()
            case .apple:
                return AppleTTSService()
            }
        }()

        vm.configure(transcription: stt, speech: tts)
    }
}
