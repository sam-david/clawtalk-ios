import Testing
import Foundation
@testable import ClawTalk

@Suite("OpenResponses API Types")
struct OpenResponsesTypesTests {

    // MARK: - Request Encoding

    @Test("Text-only message encodes correctly")
    func textOnlyMessage() throws {
        let request = OpenResponsesRequest(
            model: "openclaw:main",
            input: .items([
                .init(type: "message", role: "user", content: .text("Hello agent"))
            ]),
            stream: true,
            user: "ios-test"
        )

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["model"] as? String == "openclaw:main")
        #expect(json["stream"] as? Bool == true)
        #expect(json["user"] as? String == "ios-test")

        let input = json["input"] as! [[String: Any]]
        #expect(input.count == 1)
        #expect(input[0]["type"] as? String == "message")
        #expect(input[0]["role"] as? String == "user")
        #expect(input[0]["content"] as? String == "Hello agent")
    }

    @Test("Multi-turn conversation encodes as item array")
    func multiTurnConversation() throws {
        let request = OpenResponsesRequest(
            model: "openclaw:main",
            input: .items([
                .init(type: "message", role: "user", content: .text("What is 2+2?")),
                .init(type: "message", role: "assistant", content: .text("4")),
                .init(type: "message", role: "user", content: .text("And 3+3?")),
            ]),
            stream: true,
            user: nil
        )

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let input = json["input"] as! [[String: Any]]
        #expect(input.count == 3)
        #expect(input[0]["role"] as? String == "user")
        #expect(input[1]["role"] as? String == "assistant")
        #expect(input[2]["role"] as? String == "user")

        // user field should be null/absent
        #expect(json["user"] is NSNull || json["user"] == nil)
    }

    @Test("Image content part encodes with base64 source")
    func imageContentPart() throws {
        let request = OpenResponsesRequest(
            model: "openclaw:main",
            input: .items([
                .init(type: "message", role: "user", content: .parts([
                    .inputText("What's in this image?"),
                    .inputImage(mediaType: "image/jpeg", base64Data: "abc123=="),
                ]))
            ]),
            stream: true,
            user: nil
        )

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let input = json["input"] as! [[String: Any]]
        let parts = input[0]["content"] as! [[String: Any]]
        #expect(parts.count == 2)

        // Text part
        #expect(parts[0]["type"] as? String == "input_text")
        #expect(parts[0]["text"] as? String == "What's in this image?")

        // Image part
        #expect(parts[1]["type"] as? String == "input_image")
        let source = parts[1]["source"] as! [String: String]
        #expect(source["type"] == "base64")
        #expect(source["media_type"] == "image/jpeg")
        #expect(source["data"] == "abc123==")
    }

    @Test("Simple string input encodes as plain string")
    func simpleStringInput() throws {
        let request = OpenResponsesRequest(
            model: "openclaw:main",
            input: .text("Hello"),
            stream: false,
            user: nil
        )

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["input"] as? String == "Hello")
        #expect(json["stream"] as? Bool == false)
    }

    // MARK: - SSE Event Decoding

    @Test("ResponseTextDelta decodes delta string")
    func textDeltaDecoding() throws {
        let json = """
        {"type":"response.output_text.delta","item_id":"msg_001","output_index":0,"content_index":0,"delta":"Hello"}
        """

        let delta = try JSONDecoder().decode(ResponseTextDelta.self, from: json.data(using: .utf8)!)

        #expect(delta.delta == "Hello")
    }

    @Test("ResponseCompleted decodes usage and id")
    func completedDecoding() throws {
        let json = """
        {
            "type": "response.completed",
            "response": {
                "id": "resp_abc123",
                "status": "completed",
                "usage": {
                    "input_tokens": 42,
                    "output_tokens": 128,
                    "total_tokens": 170
                }
            }
        }
        """

        let completed = try JSONDecoder().decode(ResponseCompleted.self, from: json.data(using: .utf8)!)

        #expect(completed.response.id == "resp_abc123")
        #expect(completed.response.status == "completed")
        #expect(completed.response.usage?.inputTokens == 42)
        #expect(completed.response.usage?.outputTokens == 128)
        #expect(completed.response.usage?.totalTokens == 170)
        #expect(completed.response.error == nil)
    }

    @Test("ResponseCompleted decodes failed with error")
    func failedDecoding() throws {
        let json = """
        {
            "type": "response.failed",
            "response": {
                "id": "resp_fail",
                "status": "failed",
                "usage": {
                    "input_tokens": 10,
                    "output_tokens": 0,
                    "total_tokens": 10
                },
                "error": {
                    "code": "rate_limit_exceeded",
                    "message": "Too many requests"
                }
            }
        }
        """

        let failed = try JSONDecoder().decode(ResponseCompleted.self, from: json.data(using: .utf8)!)

        #expect(failed.response.status == "failed")
        #expect(failed.response.error?.code == "rate_limit_exceeded")
        #expect(failed.response.error?.message == "Too many requests")
    }

    @Test("ResponseCompleted decodes without usage")
    func completedWithoutUsage() throws {
        let json = """
        {
            "type": "response.completed",
            "response": {
                "id": "resp_no_usage",
                "status": "completed"
            }
        }
        """

        let completed = try JSONDecoder().decode(ResponseCompleted.self, from: json.data(using: .utf8)!)

        #expect(completed.response.id == "resp_no_usage")
        #expect(completed.response.usage == nil)
    }
}
