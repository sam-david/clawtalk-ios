import Foundation

enum TTSProvider: String, Codable, CaseIterable, Identifiable {
    case elevenlabs = "ElevenLabs"
    case openai = "OpenAI"
    case apple = "Apple (Offline)"

    var id: String { rawValue }
}

enum WhisperModelSize: String, Codable, CaseIterable, Identifiable {
    case small = "small.en"
    case largeTurbo = "large-v3-turbo"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .small: return "Small (250 MB, faster)"
        case .largeTurbo: return "Large Turbo (1.6 GB, best quality)"
        }
    }
}

struct AppSettings: Codable {
    var gatewayURL: String
    var ttsProvider: TTSProvider
    var elevenLabsVoiceID: String
    var openAIVoice: String
    var whisperModelSize: WhisperModelSize
    var voiceOutputEnabled: Bool
    var voiceInputEnabled: Bool

    static let defaults = AppSettings(
        gatewayURL: "",
        ttsProvider: .openai,
        elevenLabsVoiceID: "21m00Tcm4TlvDq8ikWAM",
        openAIVoice: "alloy",
        whisperModelSize: .small,
        voiceOutputEnabled: true,
        voiceInputEnabled: true
    )
}
