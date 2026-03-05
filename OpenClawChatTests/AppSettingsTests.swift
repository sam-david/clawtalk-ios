import Testing
@testable import OpenClawChat

@Suite("App Settings")
struct AppSettingsTests {
    @Test("Defaults are sensible")
    func defaultValues() {
        let settings = AppSettings.defaults

        #expect(settings.gatewayURL.isEmpty)
        #expect(settings.ttsProvider == .openai)
        #expect(settings.voiceOutputEnabled == true)
        #expect(settings.voiceInputEnabled == true)
        #expect(settings.whisperModelSize == .small)
    }

    @Test("Settings are Codable")
    func codableRoundTrip() throws {
        var settings = AppSettings.defaults
        settings.gatewayURL = "https://openclaw.samdavid.net"
        settings.ttsProvider = .elevenlabs

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(decoded.gatewayURL == "https://openclaw.samdavid.net")
        #expect(decoded.ttsProvider == .elevenlabs)
    }

    @Test("All TTS providers have display names")
    func ttsProviderNames() {
        for provider in TTSProvider.allCases {
            #expect(!provider.rawValue.isEmpty)
            #expect(!provider.id.isEmpty)
        }
    }

    @Test("All Whisper model sizes have display names")
    func whisperModelDisplayNames() {
        for model in WhisperModelSize.allCases {
            #expect(!model.displayName.isEmpty)
            #expect(!model.rawValue.isEmpty)
        }
    }
}
