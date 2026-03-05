import SwiftUI

@main
struct OpenClawChatApp: App {
    @State private var settingsStore = SettingsStore()
    @State private var chatViewModel: ChatViewModel?

    var body: some Scene {
        WindowGroup {
            Group {
                if let viewModel = chatViewModel {
                    ChatView(viewModel: viewModel, settingsStore: settingsStore)
                } else {
                    ProgressView("Loading...")
                        .onAppear { setup() }
                }
            }
            .preferredColorScheme(.dark)
            .onChange(of: settingsStore.settings.ttsProvider) {
                reconfigureServices()
            }
            .onChange(of: settingsStore.settings.voiceInputEnabled) {
                reconfigureServices()
            }
        }
    }

    private func setup() {
        let vm = ChatViewModel(settings: settingsStore)
        configureServices(for: vm)
        chatViewModel = vm
    }

    private func reconfigureServices() {
        guard let vm = chatViewModel else { return }
        configureServices(for: vm)
    }

    private func configureServices(for vm: ChatViewModel) {
        let secure = SecureStorage.shared
        let s = settingsStore.settings

        // STT
        let stt: any TranscriptionService = WhisperKitService(modelSize: s.whisperModelSize)

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
