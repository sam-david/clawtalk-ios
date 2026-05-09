import Foundation

// Mirrors gateway protocol/schema/channels.ts (commit c434d7720b+).
// Only the surface ClawTalk consumes today: mode="transcription",
// transport="gateway-relay", brain="none".

enum TalkMode: String, Codable, Sendable {
    case realtime
    case sttTts = "stt-tts"
    case transcription
}

enum TalkTransport: String, Codable, Sendable {
    case gatewayRelay = "gateway-relay"
    case managedRoom = "managed-room"
}

enum TalkBrain: String, Codable, Sendable {
    case none
    case agentConsult = "agent-consult"
    case directTools = "direct-tools"
}

struct TalkSessionCreateParams: Encodable, Sendable {
    let sessionKey: String?
    let provider: String?
    let model: String?
    let voice: String?
    let mode: TalkMode?
    let transport: TalkTransport?
    let brain: TalkBrain?
    let ttlMs: Int?
}

struct TalkSessionCreateResult: Decodable, Sendable {
    let sessionId: String
    let mode: TalkMode
    let transport: TalkTransport
    let brain: TalkBrain
    let transcriptionSessionId: String?
}

struct TalkSessionAppendAudioParams: Encodable, Sendable {
    let sessionId: String
    let audioBase64: String
    let timestamp: Double?
}

struct TalkSessionCloseParams: Encodable, Sendable {
    let sessionId: String
}

// MARK: - Inbound talk events (channel "talk.event")

enum TalkEventType: String, Codable, Sendable {
    case sessionReady = "session.ready"
    case sessionClosed = "session.closed"
    case sessionError = "session.error"
    case sessionReplaced = "session.replaced"
    case turnStarted = "turn.started"
    case turnEnded = "turn.ended"
    case turnCancelled = "turn.cancelled"
    case captureStarted = "capture.started"
    case captureStopped = "capture.stopped"
    case captureCancelled = "capture.cancelled"
    case captureOnce = "capture.once"
    case inputAudioDelta = "input.audio.delta"
    case inputAudioCommitted = "input.audio.committed"
    case transcriptDelta = "transcript.delta"
    case transcriptDone = "transcript.done"
    case outputTextDelta = "output.text.delta"
    case outputTextDone = "output.text.done"
    case outputAudioStarted = "output.audio.started"
    case outputAudioDelta = "output.audio.delta"
    case outputAudioDone = "output.audio.done"
    case toolCall = "tool.call"
    case toolProgress = "tool.progress"
    case toolResult = "tool.result"
    case toolError = "tool.error"
    case usageMetrics = "usage.metrics"
    case latencyMetrics = "latency.metrics"
    case healthChanged = "health.changed"
}

struct TalkEventPayload: Decodable, Sendable {
    let id: String
    let type: TalkEventType
    let sessionId: String
    let turnId: String?
    let captureId: String?
    let seq: Int
    let timestamp: String
    let data: AnyCodable?

    private enum CodingKeys: String, CodingKey {
        case id, type, sessionId, turnId, captureId, seq, timestamp, data
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decode(TalkEventType.self, forKey: .type)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        turnId = try c.decodeIfPresent(String.self, forKey: .turnId)
        captureId = try c.decodeIfPresent(String.self, forKey: .captureId)
        seq = try c.decode(Int.self, forKey: .seq)
        timestamp = try c.decode(String.self, forKey: .timestamp)
        data = try c.decodeIfPresent(AnyCodable.self, forKey: .data)
    }
}

// Convenience accessors for the transcription-mode events ClawTalk reads.
extension TalkEventPayload {
    private var dict: [String: AnyCodable]? {
        data?.value as? [String: AnyCodable]
    }

    /// For transcript.delta / transcript.done events.
    var transcriptText: String? {
        guard let dict else { return nil }
        return dict["text"]?.value as? String ?? dict["transcript"]?.value as? String
    }

    /// For session.error events.
    var errorMessage: String? {
        guard let dict else { return nil }
        return dict["message"]?.value as? String ?? dict["error"]?.value as? String
    }
}
