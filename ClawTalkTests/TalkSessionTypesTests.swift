import Testing
import Foundation
@testable import ClawTalk

@Suite("Talk Session Types")
struct TalkSessionTypesTests {

    // MARK: - Request encoding

    @Test("TalkSessionCreateParams encodes mode/transport/brain raw values")
    func encodesCreateParams() throws {
        let params = TalkSessionCreateParams(
            sessionKey: "agent:main:client:abcd",
            provider: "openai",
            model: "gpt-4o-mini-transcribe",
            voice: nil,
            mode: .transcription,
            transport: .gatewayRelay,
            brain: TalkBrain.none,
            ttlMs: 600_000
        )
        let data = try JSONEncoder().encode(params)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(dict["sessionKey"] as? String == "agent:main:client:abcd")
        #expect(dict["provider"] as? String == "openai")
        #expect(dict["model"] as? String == "gpt-4o-mini-transcribe")
        #expect(dict["mode"] as? String == "transcription")
        #expect(dict["transport"] as? String == "gateway-relay")
        #expect(dict["brain"] as? String == "none")
        #expect(dict["ttlMs"] as? Int == 600_000)
        #expect(dict["voice"] == nil)  // nil omitted unless explicitly encoded
    }

    @Test("TalkSessionAppendAudioParams encodes")
    func encodesAppendAudio() throws {
        let params = TalkSessionAppendAudioParams(
            sessionId: "sess_123",
            audioBase64: "AAAA",
            timestamp: 1.5
        )
        let data = try JSONEncoder().encode(params)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(dict["sessionId"] as? String == "sess_123")
        #expect(dict["audioBase64"] as? String == "AAAA")
        #expect(dict["timestamp"] as? Double == 1.5)
    }

    // MARK: - Result decoding

    @Test("TalkSessionCreateResult decodes minimum payload")
    func decodesCreateResult() throws {
        let json = """
        {
            "sessionId": "sess_abc",
            "mode": "transcription",
            "transport": "gateway-relay",
            "brain": "none"
        }
        """
        let result = try JSONDecoder().decode(TalkSessionCreateResult.self, from: json.data(using: .utf8)!)
        #expect(result.sessionId == "sess_abc")
        #expect(result.mode == .transcription)
        #expect(result.transport == .gatewayRelay)
        #expect(result.brain == TalkBrain.none)
        #expect(result.transcriptionSessionId == nil)
    }

    @Test("TalkSessionCreateResult decodes optional transcriptionSessionId")
    func decodesCreateResultWithTranscriptionId() throws {
        let json = """
        {
            "sessionId": "sess_abc",
            "mode": "transcription",
            "transport": "gateway-relay",
            "brain": "none",
            "transcriptionSessionId": "tx_xyz"
        }
        """
        let result = try JSONDecoder().decode(TalkSessionCreateResult.self, from: json.data(using: .utf8)!)
        #expect(result.transcriptionSessionId == "tx_xyz")
    }

    // MARK: - Event decoding

    @Test("TalkEventPayload decodes session.ready")
    func decodesSessionReady() throws {
        let json = """
        {"id":"e1","type":"session.ready","sessionId":"sess_1","seq":1,"timestamp":"2026-01-01T00:00:00Z"}
        """
        let evt = try JSONDecoder().decode(TalkEventPayload.self, from: json.data(using: .utf8)!)
        #expect(evt.type == .sessionReady)
        #expect(evt.sessionId == "sess_1")
        #expect(evt.seq == 1)
        #expect(evt.turnId == nil)
    }

    @Test("TalkEventPayload decodes transcript.delta with text")
    func decodesTranscriptDelta() throws {
        let json = """
        {"id":"e2","type":"transcript.delta","sessionId":"sess_1","turnId":"t1","seq":2,"timestamp":"2026-01-01T00:00:00Z","data":{"text":"hello"}}
        """
        let evt = try JSONDecoder().decode(TalkEventPayload.self, from: json.data(using: .utf8)!)
        #expect(evt.type == .transcriptDelta)
        #expect(evt.transcriptText == "hello")
    }

    @Test("TalkEventPayload decodes transcript.done with transcript field name")
    func decodesTranscriptDoneAlternate() throws {
        // Some providers use "transcript" instead of "text" for the final.
        let json = """
        {"id":"e3","type":"transcript.done","sessionId":"sess_1","turnId":"t1","seq":3,"timestamp":"2026-01-01T00:00:00Z","data":{"transcript":"hello world"}}
        """
        let evt = try JSONDecoder().decode(TalkEventPayload.self, from: json.data(using: .utf8)!)
        #expect(evt.type == .transcriptDone)
        #expect(evt.transcriptText == "hello world")
    }

    @Test("TalkEventPayload decodes session.error message")
    func decodesSessionError() throws {
        let json = """
        {"id":"e4","type":"session.error","sessionId":"sess_1","seq":1,"timestamp":"2026-01-01T00:00:00Z","data":{"message":"upstream timeout"}}
        """
        let evt = try JSONDecoder().decode(TalkEventPayload.self, from: json.data(using: .utf8)!)
        #expect(evt.type == .sessionError)
        #expect(evt.errorMessage == "upstream timeout")
    }

    @Test("TalkEventPayload returns nil text for unrelated events")
    func unrelatedEventHasNilTranscript() throws {
        let json = """
        {"id":"e5","type":"capture.started","sessionId":"sess_1","captureId":"c1","seq":1,"timestamp":"2026-01-01T00:00:00Z"}
        """
        let evt = try JSONDecoder().decode(TalkEventPayload.self, from: json.data(using: .utf8)!)
        #expect(evt.type == .captureStarted)
        #expect(evt.transcriptText == nil)
        #expect(evt.captureId == "c1")
    }

    @Test("TalkMode/Transport/Brain raw values match gateway schema")
    func rawValuesMatchSchema() {
        #expect(TalkMode.realtime.rawValue == "realtime")
        #expect(TalkMode.sttTts.rawValue == "stt-tts")
        #expect(TalkMode.transcription.rawValue == "transcription")
        #expect(TalkTransport.gatewayRelay.rawValue == "gateway-relay")
        #expect(TalkTransport.managedRoom.rawValue == "managed-room")
        #expect(TalkBrain.none.rawValue == "none")
        #expect(TalkBrain.agentConsult.rawValue == "agent-consult")
        #expect(TalkBrain.directTools.rawValue == "direct-tools")
    }
}
