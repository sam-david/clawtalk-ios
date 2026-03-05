import SwiftUI

struct SettingsView: View {
    @Bindable var store: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                connectionSection
                voiceSection
                ttsSection
                sttSection
                securitySection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Connection

    private var connectionSection: some View {
        Section {
            TextField("https://openclaw.samdavid.net", text: $store.settings.gatewayURL)
                .textContentType(.URL)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            SecureField("Gateway Token", text: $store.gatewayToken)
                .textContentType(.password)
        } header: {
            Text("OpenClaw Gateway")
        } footer: {
            Text("Your gateway URL (Cloudflare tunnel or Tailscale). Only HTTPS connections are allowed.")
        }
    }

    // MARK: - Voice Toggle

    private var voiceSection: some View {
        Section {
            Toggle("Voice Input (STT)", isOn: $store.settings.voiceInputEnabled)
            Toggle("Voice Output (TTS)", isOn: $store.settings.voiceOutputEnabled)
        } header: {
            Text("Voice")
        } footer: {
            Text("Disable voice for text-only chat. Voice input uses on-device transcription.")
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

    private var sttSection: some View {
        Section {
            Picker("Whisper Model", selection: $store.settings.whisperModelSize) {
                ForEach(WhisperModelSize.allCases) { model in
                    Text(model.displayName).tag(model)
                }
            }
        } header: {
            Text("Speech-to-Text")
        } footer: {
            Text("Runs entirely on-device. The model is downloaded on first use. Large Turbo requires ~1.6 GB of storage but provides the best accuracy.")
        }
    }

    // MARK: - Security Info

    private var securitySection: some View {
        Section {
            LabeledContent("Token Storage", value: "iOS Keychain")
            LabeledContent("Transport", value: "HTTPS Only")
            LabeledContent("STT Processing", value: "On-Device")
        } header: {
            Text("Security")
        } footer: {
            Text("API keys and tokens are stored in the iOS Keychain, encrypted at rest. Voice is transcribed on-device — audio never leaves your phone. Agent communication uses HTTPS.")
        }
    }
}
