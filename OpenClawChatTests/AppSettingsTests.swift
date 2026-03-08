import Testing
import Foundation
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
        #expect(settings.agentAPIMode == .openResponses)
        #expect(settings.showTokenUsage == false)
    }

    @Test("Settings are Codable")
    func codableRoundTrip() throws {
        var settings = AppSettings.defaults
        settings.gatewayURL = "https://openclaw.samdavid.net"
        settings.ttsProvider = .elevenlabs
        settings.agentAPIMode = .openResponses
        settings.showTokenUsage = true

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(decoded.gatewayURL == "https://openclaw.samdavid.net")
        #expect(decoded.ttsProvider == .elevenlabs)
        #expect(decoded.agentAPIMode == .openResponses)
        #expect(decoded.showTokenUsage == true)
    }

    @Test("Old settings without new fields decode with defaults")
    func backwardCompatibility() throws {
        // Simulate saved JSON from before agentAPIMode/showTokenUsage existed
        let oldJSON = """
        {
            "gatewayURL": "https://openclaw.samdavid.net",
            "ttsProvider": "OpenAI",
            "elevenLabsVoiceID": "21m00Tcm4TlvDq8ikWAM",
            "openAIVoice": "alloy",
            "whisperModelSize": "small.en",
            "voiceOutputEnabled": true,
            "voiceInputEnabled": true
        }
        """

        let decoded = try JSONDecoder().decode(AppSettings.self, from: oldJSON.data(using: .utf8)!)

        // Existing fields preserved
        #expect(decoded.gatewayURL == "https://openclaw.samdavid.net")
        #expect(decoded.ttsProvider == .openai)

        // New fields get defaults
        #expect(decoded.agentAPIMode == .openResponses)
        #expect(decoded.showTokenUsage == false)
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

    @Test("All API modes have identifiers")
    func apiModeIdentifiers() {
        for mode in AgentAPIMode.allCases {
            #expect(!mode.rawValue.isEmpty)
            #expect(!mode.id.isEmpty)
        }
    }
}
