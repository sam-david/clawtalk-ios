import SwiftUI

@main
struct OpenClawChatApp: App {
    @State private var settingsStore = SettingsStore()
    @State private var channelStore = ChannelStore()
    @State private var selectedChannel: Channel?
    @State private var chatViewModel: ChatViewModel?
    @State private var showModelDownload = false
    @State private var modelManager = WhisperModelManager.shared
    @State private var cachedSTT: WhisperKitService?
    @State private var cachedSTTModelSize: WhisperModelSize?

    var body: some Scene {
        WindowGroup {
            Group {
                if showModelDownload {
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
                    ChatView(viewModel: vm, settingsStore: settingsStore, onBack: goBack, onDeleteChannel: deleteCurrentChannel)
                } else {
                    ChannelListView(
                        channelStore: channelStore,
                        settingsStore: settingsStore,
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
            .preferredColorScheme(.dark)
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
        let vm = ChatViewModel(settings: settingsStore, channel: channel, channelStore: channelStore)
        configureServices(for: vm)
        chatViewModel = vm
        selectedChannel = channel
    }

    private func goBack() {
        chatViewModel?.stop()
        chatViewModel = nil
        selectedChannel = nil
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
