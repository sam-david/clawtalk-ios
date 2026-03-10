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
    var useWebSocket: Bool
    var webSocketPath: String
    var hapticsEnabled: Bool

    static let defaults = AppSettings(
        gatewayURL: "",
        ttsProvider: .openai,
        elevenLabsVoiceID: "21m00Tcm4TlvDq8ikWAM",
        openAIVoice: "alloy",
        whisperModelSize: .small,
        voiceOutputEnabled: true,
        voiceInputEnabled: true,
        agentAPIMode: .openResponses,
        showTokenUsage: false,
        useWebSocket: false,
        webSocketPath: "/ws",
        hapticsEnabled: true
    )

    /// Build the full WebSocket URL from the gateway URL + port/path override.
    /// Examples:
    ///   gateway=https://example.com, wsPortOrPath=/ws       →  wss://example.com/ws
    ///   gateway=https://example.com, wsPortOrPath=ws        →  wss://example.com/ws
    ///   gateway=http://192.168.1.5,  wsPortOrPath=18789     →  ws://192.168.1.5:18789
    ///   gateway=http://192.168.1.5,  wsPortOrPath=:18789    →  ws://192.168.1.5:18789
    var resolvedWebSocketURL: String {
        let base = gatewayURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(string: base) else { return "" }

        let sourceScheme = components.scheme?.lowercased() ?? "https"
        components.scheme = (sourceScheme == "http") ? "ws" : "wss"

        let input = webSocketPath.trimmingCharacters(in: .whitespaces)

        // Strip optional leading colon for port input
        let normalized = input.hasPrefix(":") ? String(input.dropFirst()) : input

        if normalized.isEmpty {
            // Empty — use default port 18789
            components.port = 18789
            components.path = ""
        } else if let port = Int(normalized) {
            // Pure number → port (e.g. "18789" or ":18789")
            components.port = port
            components.path = ""
        } else {
            // String → path (e.g. "/ws", "ws")
            components.port = nil
            components.path = normalized.hasPrefix("/") ? normalized : "/\(normalized)"
        }

        return components.url?.absoluteString ?? ""
    }

    init(
        gatewayURL: String,
        ttsProvider: TTSProvider,
        elevenLabsVoiceID: String,
        openAIVoice: String,
        whisperModelSize: WhisperModelSize,
        voiceOutputEnabled: Bool,
        voiceInputEnabled: Bool,
        agentAPIMode: AgentAPIMode = .openResponses,
        showTokenUsage: Bool = false,
        useWebSocket: Bool = false,
        webSocketPath: String = "/ws",
        hapticsEnabled: Bool = true
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
        self.useWebSocket = useWebSocket
        self.webSocketPath = webSocketPath
        self.hapticsEnabled = hapticsEnabled
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
        agentAPIMode = try container.decodeIfPresent(AgentAPIMode.self, forKey: .agentAPIMode) ?? .openResponses
        showTokenUsage = try container.decodeIfPresent(Bool.self, forKey: .showTokenUsage) ?? false
        useWebSocket = try container.decodeIfPresent(Bool.self, forKey: .useWebSocket) ?? false
        hapticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? true

        // Migrate legacy webSocketPort → webSocketPath
        if let legacyPort = try container.decodeIfPresent(Int.self, forKey: .webSocketPort) {
            webSocketPath = ":\(legacyPort)"
        } else {
            webSocketPath = try container.decodeIfPresent(String.self, forKey: .webSocketPath) ?? "/ws"
        }
    }

    enum CodingKeys: String, CodingKey {
        case gatewayURL, ttsProvider, elevenLabsVoiceID, openAIVoice
        case whisperModelSize, voiceOutputEnabled, voiceInputEnabled
        case agentAPIMode, showTokenUsage, useWebSocket
        case webSocketPath, webSocketPort // webSocketPort for legacy decode only
        case hapticsEnabled
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(gatewayURL, forKey: .gatewayURL)
        try container.encode(ttsProvider, forKey: .ttsProvider)
        try container.encode(elevenLabsVoiceID, forKey: .elevenLabsVoiceID)
        try container.encode(openAIVoice, forKey: .openAIVoice)
        try container.encode(whisperModelSize, forKey: .whisperModelSize)
        try container.encode(voiceOutputEnabled, forKey: .voiceOutputEnabled)
        try container.encode(voiceInputEnabled, forKey: .voiceInputEnabled)
        try container.encode(agentAPIMode, forKey: .agentAPIMode)
        try container.encode(showTokenUsage, forKey: .showTokenUsage)
        try container.encode(useWebSocket, forKey: .useWebSocket)
        try container.encode(webSocketPath, forKey: .webSocketPath)
        try container.encode(hapticsEnabled, forKey: .hapticsEnabled)
        // webSocketPort intentionally not encoded — legacy only
    }
}
