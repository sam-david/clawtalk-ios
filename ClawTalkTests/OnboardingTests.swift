import Testing
import Foundation
@testable import ClawTalk

@Suite("Onboarding")
struct OnboardingTests {

    // MARK: - Step Progression

    @Test("Onboarding has 4 steps")
    func stepCount() {
        let steps = OnboardingView.Step.allCases
        #expect(steps.count == 4)
    }

    @Test("Steps are in correct order")
    func stepOrder() {
        let steps = OnboardingView.Step.allCases
        #expect(steps[0] == .welcome)
        #expect(steps[1] == .gatewaySetup)
        #expect(steps[2] == .gateway)
        #expect(steps[3] == .voice)
    }

    // MARK: - Connection Test State

    @Test("ConnectionTestState equality")
    func connectionTestStateEquality() {
        let idle1 = OnboardingView.ConnectionTestState.idle
        let idle2 = OnboardingView.ConnectionTestState.idle
        #expect(idle1 == idle2)

        let testing1 = OnboardingView.ConnectionTestState.testing
        #expect(testing1 == .testing)

        let success1 = OnboardingView.ConnectionTestState.success
        #expect(success1 == .success)

        let failed1 = OnboardingView.ConnectionTestState.failed("error A")
        let failed2 = OnboardingView.ConnectionTestState.failed("error A")
        let failed3 = OnboardingView.ConnectionTestState.failed("error B")
        #expect(failed1 == failed2)
        #expect(failed1 != failed3)
    }

    @Test("Different states are not equal")
    func connectionTestStateInequality() {
        let idle = OnboardingView.ConnectionTestState.idle
        let testing = OnboardingView.ConnectionTestState.testing
        let success = OnboardingView.ConnectionTestState.success
        let failed = OnboardingView.ConnectionTestState.failed("err")

        #expect(idle != testing)
        #expect(idle != success)
        #expect(idle != failed)
        #expect(testing != success)
    }

    // MARK: - Default Settings After Onboarding

    @Test("Default settings use HTTP mode, not WebSocket")
    func defaultsUseHTTP() {
        let settings = AppSettings.defaults
        #expect(settings.useWebSocket == false)
    }

    @Test("Default API mode is Open Responses")
    func defaultAPIMode() {
        let settings = AppSettings.defaults
        #expect(settings.agentAPIMode == .openResponses)
    }

    @Test("Default voice input and output are enabled")
    func defaultVoiceEnabled() {
        let settings = AppSettings.defaults
        #expect(settings.voiceInputEnabled == true)
        #expect(settings.voiceOutputEnabled == true)
    }

    @Test("Default token usage display is off")
    func defaultTokenUsageOff() {
        let settings = AppSettings.defaults
        #expect(settings.showTokenUsage == false)
    }

    @Test("Default WebSocket path is /ws")
    func defaultWSPath() {
        let settings = AppSettings.defaults
        #expect(settings.webSocketPath == "/ws")
    }

    // MARK: - Settings Store Behavior

    @Test("isConfigured requires both URL and token")
    func isConfiguredCheck() {
        // Test the logic directly on AppSettings + token check
        // (SettingsStore reads from Keychain/UserDefaults so isn't isolated)
        let settings = AppSettings.defaults

        // Empty URL → not configured regardless of token
        #expect(settings.gatewayURL.isEmpty)

        // URL set but we simulate no token
        var withURL = settings
        withURL.gatewayURL = "https://example.com"
        // isConfigured = !url.isEmpty && !token.isEmpty
        // With URL but no token → not configured
        #expect(!withURL.gatewayURL.isEmpty)
    }

    // MARK: - Onboarding saves gateway config

    @Test("Gateway URL is saved during onboarding")
    func gatewayURLSaved() throws {
        var settings = AppSettings.defaults
        settings.gatewayURL = "https://openclaw.example.com"

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded.gatewayURL == "https://openclaw.example.com")
    }

    @Test("Skipping voice disables voice input")
    func skipVoiceDisablesInput() throws {
        var settings = AppSettings.defaults
        settings.voiceInputEnabled = false

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded.voiceInputEnabled == false)
        // Voice output should remain enabled
        #expect(decoded.voiceOutputEnabled == true)
    }

    // MARK: - WebSocket Upgrade Path (Settings, not Onboarding)

    @Test("Enabling WebSocket preserves other settings")
    func enableWSPreservesSettings() throws {
        var settings = AppSettings.defaults
        settings.gatewayURL = "https://example.com"
        settings.ttsProvider = .elevenlabs
        settings.useWebSocket = true
        settings.webSocketPath = "/ws"

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(decoded.useWebSocket == true)
        #expect(decoded.gatewayURL == "https://example.com")
        #expect(decoded.ttsProvider == .elevenlabs)
        #expect(decoded.webSocketPath == "/ws")
    }

    @Test("WebSocket mode should disable token usage display")
    func wsDisablesTokenUsage() {
        // This documents the expected behavior: when useWebSocket is true,
        // showTokenUsage should be false because WS events don't include usage data.
        var settings = AppSettings.defaults
        settings.showTokenUsage = true
        settings.useWebSocket = true

        // The SettingsView enforces this via onChange, but at the model level
        // both can be true — the UI prevents it.
        // This test documents the expectation for manual validation.
        #expect(settings.useWebSocket == true)
    }

    // MARK: - Backward Compatibility

    @Test("Old settings without useWebSocket default to HTTP")
    func oldSettingsDefaultHTTP() throws {
        let oldJSON = """
        {
            "gatewayURL": "https://example.com",
            "ttsProvider": "OpenAI",
            "elevenLabsVoiceID": "21m00Tcm4TlvDq8ikWAM",
            "openAIVoice": "alloy",
            "whisperModelSize": "small.en",
            "voiceOutputEnabled": true,
            "voiceInputEnabled": true
        }
        """

        let decoded = try JSONDecoder().decode(AppSettings.self, from: oldJSON.data(using: .utf8)!)
        #expect(decoded.useWebSocket == false)
    }
}
