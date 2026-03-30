import Testing
import Foundation
@testable import ClawTalk

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
        #expect(settings.useWebSocket == false)
        #expect(settings.webSocketPath == "/ws")
        #expect(settings.hapticsEnabled == true)
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

    // MARK: - WebSocket URL Resolution

    @Test("WebSocket URL with path for tunneled gateways")
    func wsURLPath() {
        var settings = AppSettings.defaults
        settings.gatewayURL = "https://openclaw.example.com"
        settings.webSocketPath = "/ws"
        #expect(settings.resolvedWebSocketURL == "wss://openclaw.example.com/ws")
    }

    @Test("WebSocket URL with path without leading slash")
    func wsURLPathNoSlash() {
        var settings = AppSettings.defaults
        settings.gatewayURL = "https://openclaw.example.com"
        settings.webSocketPath = "ws"
        #expect(settings.resolvedWebSocketURL == "wss://openclaw.example.com/ws")
    }

    @Test("WebSocket URL with port for local connections")
    func wsURLPort() {
        var settings = AppSettings.defaults
        settings.gatewayURL = "http://192.168.1.5"
        settings.webSocketPath = "18789"
        #expect(settings.resolvedWebSocketURL == "ws://192.168.1.5:18789")
    }

    @Test("WebSocket URL with colon-prefixed port")
    func wsURLColonPort() {
        var settings = AppSettings.defaults
        settings.gatewayURL = "http://192.168.1.5"
        settings.webSocketPath = ":18789"
        #expect(settings.resolvedWebSocketURL == "ws://192.168.1.5:18789")
    }

    @Test("WebSocket URL with empty path defaults to port 18789")
    func wsURLEmptyPath() {
        var settings = AppSettings.defaults
        settings.gatewayURL = "http://192.168.1.5"
        settings.webSocketPath = ""
        #expect(settings.resolvedWebSocketURL == "ws://192.168.1.5:18789")
    }

    @Test("WebSocket URL uses wss for https gateway")
    func wsURLSchemeHttps() {
        var settings = AppSettings.defaults
        settings.gatewayURL = "https://example.com"
        settings.webSocketPath = "/ws"
        #expect(settings.resolvedWebSocketURL.hasPrefix("wss://"))
    }

    @Test("WebSocket URL uses ws for http gateway")
    func wsURLSchemeHttp() {
        var settings = AppSettings.defaults
        settings.gatewayURL = "http://localhost"
        settings.webSocketPath = "18789"
        #expect(settings.resolvedWebSocketURL.hasPrefix("ws://"))
    }

    // MARK: - Legacy Migration

    @Test("Legacy webSocketPort migrates to webSocketPath")
    func legacyPortMigration() throws {
        let legacyJSON = """
        {
            "gatewayURL": "https://example.com",
            "ttsProvider": "OpenAI",
            "elevenLabsVoiceID": "21m00Tcm4TlvDq8ikWAM",
            "openAIVoice": "alloy",
            "whisperModelSize": "small.en",
            "voiceOutputEnabled": true,
            "voiceInputEnabled": true,
            "webSocketPort": 18789
        }
        """

        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacyJSON.data(using: .utf8)!)
        #expect(decoded.webSocketPath == ":18789")
    }

    @Test("webSocketPort is not encoded (legacy only)")
    func legacyPortNotEncoded() throws {
        var settings = AppSettings.defaults
        settings.webSocketPath = "/ws"

        let data = try JSONEncoder().encode(settings)
        let json = String(data: data, encoding: .utf8)!
        #expect(!json.contains("webSocketPort"))
        #expect(json.contains("webSocketPath"))
    }
}
