import Foundation

enum TTSProvider: String, Codable, CaseIterable, Identifiable {
    case elevenlabs = "ElevenLabs"
    case openai = "OpenAI"
    case apple = "Apple (Offline)"

    var id: String { rawValue }
}

enum AgentAPIMode: String, Codable, CaseIterable, Identifiable {
    case chatCompletions = "Chat Completions"
    case openResponses = "Open Responses"

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
    var agentAPIMode: AgentAPIMode
    var showTokenUsage: Bool

    static let defaults = AppSettings(
        gatewayURL: "",
        ttsProvider: .openai,
        elevenLabsVoiceID: "21m00Tcm4TlvDq8ikWAM",
        openAIVoice: "alloy",
        whisperModelSize: .small,
        voiceOutputEnabled: true,
        voiceInputEnabled: true,
        agentAPIMode: .chatCompletions,
        showTokenUsage: false
    )

    init(
        gatewayURL: String,
        ttsProvider: TTSProvider,
        elevenLabsVoiceID: String,
        openAIVoice: String,
        whisperModelSize: WhisperModelSize,
        voiceOutputEnabled: Bool,
        voiceInputEnabled: Bool,
        agentAPIMode: AgentAPIMode = .chatCompletions,
        showTokenUsage: Bool = false
    ) {
        self.gatewayURL = gatewayURL
        self.ttsProvider = ttsProvider
        self.elevenLabsVoiceID = elevenLabsVoiceID
        self.openAIVoice = openAIVoice
        self.whisperModelSize = whisperModelSize
        self.voiceOutputEnabled = voiceOutputEnabled
        self.voiceInputEnabled = voiceInputEnabled
        self.agentAPIMode = agentAPIMode
        self.showTokenUsage = showTokenUsage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gatewayURL = try container.decode(String.self, forKey: .gatewayURL)
        ttsProvider = try container.decode(TTSProvider.self, forKey: .ttsProvider)
        elevenLabsVoiceID = try container.decode(String.self, forKey: .elevenLabsVoiceID)
        openAIVoice = try container.decode(String.self, forKey: .openAIVoice)
        whisperModelSize = try container.decode(WhisperModelSize.self, forKey: .whisperModelSize)
        voiceOutputEnabled = try container.decode(Bool.self, forKey: .voiceOutputEnabled)
        voiceInputEnabled = try container.decode(Bool.self, forKey: .voiceInputEnabled)
        agentAPIMode = try container.decodeIfPresent(AgentAPIMode.self, forKey: .agentAPIMode) ?? .chatCompletions
        showTokenUsage = try container.decodeIfPresent(Bool.self, forKey: .showTokenUsage) ?? false
    }
}
