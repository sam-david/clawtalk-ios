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

/// The gateway broadcasts on the `talk.event` topic with a wrapper
/// payload — the actual TalkEvent is nested inside a `talkEvent` field,
/// alongside relay metadata. Transcript text in particular sits at the
/// OUTER wrapper level (`text`, `final`), NOT inside the nested
/// talkEvent.data. See src/gateway/talk-transcription-relay.ts
/// (broadcastToOwner).
struct TalkEventEnvelope: Decodable, Sendable {
    /// Optional wrapper-level transcript text (transcript.delta / .done).
    let text: String?
    /// Optional wrapper-level "final" flag on transcripts.
    let final: Bool?
    /// The actual TalkEvent (session.ready, transcript.done, …).
    let talkEvent: TalkEventPayload?
}

extension TalkEventPayload {
    /// Build a copy of this payload with `data` replaced by the given
    /// dictionary. Used when the relay envelope carries transcript
    /// text at the outer level — we splice it into the inner event's
    /// data so the existing transcriptText accessor finds it.
    func replacingData(with dict: [String: AnyCodable]) -> TalkEventPayload {
        let json: [String: Any] = [
            "id": id,
            "type": type.rawValue,
            "sessionId": sessionId,
            "turnId": turnId as Any,
            "captureId": captureId as Any,
            "seq": seq,
            "timestamp": timestamp,
            "data": dict.mapValues { $0.value },
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let copy = try? JSONDecoder().decode(TalkEventPayload.self, from: data)
        else {
            return self
        }
        return copy
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
