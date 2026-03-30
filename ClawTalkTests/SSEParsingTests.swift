import Testing
import Foundation
@testable import ClawTalk

@Suite("SSE Parsing")
struct SSEParsingTests {

    // MARK: - Chat Completions Chunk Parsing

    @Test("Parses delta with content")
    func parseDeltaContent() throws {
        let json = """
        {"id":"chatcmpl-1","model":"claude-sonnet","choices":[{"delta":{"content":"Hello "},"finish_reason":null}]}
        """
        let chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: json.data(using: .utf8)!)

        #expect(chunk.id == "chatcmpl-1")
        #expect(chunk.model == "claude-sonnet")
        #expect(chunk.choices.count == 1)
        #expect(chunk.choices[0].delta?.content == "Hello ")
        #expect(chunk.choices[0].finishReason == nil)
    }

    @Test("Parses chunk with stop finish reason")
    func parseStopReason() throws {
        let json = """
        {"id":"chatcmpl-1","choices":[{"delta":{},"finish_reason":"stop"}]}
        """
        let chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: json.data(using: .utf8)!)
        #expect(chunk.choices[0].finishReason == "stop")
    }

    @Test("Parses chunk with null model")
    func parseNullModel() throws {
        let json = """
        {"id":"chatcmpl-1","model":null,"choices":[{"delta":{"content":"hi"}}]}
        """
        let chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: json.data(using: .utf8)!)
        #expect(chunk.model == nil)
    }

    @Test("Parses chunk without model field")
    func parseMissingModel() throws {
        let json = """
        {"id":"chatcmpl-1","choices":[{"delta":{"content":"hi"}}]}
        """
        let chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: json.data(using: .utf8)!)
        #expect(chunk.model == nil)
    }

    @Test("Parses chunk with empty delta")
    func parseEmptyDelta() throws {
        let json = """
        {"id":"chatcmpl-1","choices":[{"delta":{}}]}
        """
        let chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: json.data(using: .utf8)!)
        #expect(chunk.choices[0].delta?.content == nil)
    }

    @Test("Parses chunk with role in delta")
    func parseRoleDelta() throws {
        let json = """
        {"id":"chatcmpl-1","choices":[{"delta":{"role":"assistant"}}]}
        """
        let chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: json.data(using: .utf8)!)
        #expect(chunk.choices[0].delta?.role == "assistant")
    }

    @Test("Handles multiple choices")
    func multipleChoices() throws {
        let json = """
        {"id":"chatcmpl-1","choices":[{"delta":{"content":"A"}},{"delta":{"content":"B"}}]}
        """
        let chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: json.data(using: .utf8)!)
        #expect(chunk.choices.count == 2)
        #expect(chunk.choices[0].delta?.content == "A")
        #expect(chunk.choices[1].delta?.content == "B")
    }

    // MARK: - Open Responses Event Parsing

    @Test("Parses response text delta")
    func parseTextDelta() throws {
        let json = """
        {"type":"response.output_text.delta","delta":"world"}
        """
        let delta = try JSONDecoder().decode(ResponseTextDelta.self, from: json.data(using: .utf8)!)
        #expect(delta.delta == "world")
    }

    @Test("Parses response completed with full usage")
    func parseCompleted() throws {
        let json = """
        {
            "type": "response.completed",
            "response": {
                "id": "resp_123",
                "model": "anthropic/claude-sonnet",
                "status": "completed",
                "usage": {
                    "input_tokens": 100,
                    "output_tokens": 50,
                    "total_tokens": 150
                }
            }
        }
        """
        let completed = try JSONDecoder().decode(ResponseCompleted.self, from: json.data(using: .utf8)!)

        #expect(completed.response.id == "resp_123")
        #expect(completed.response.model == "anthropic/claude-sonnet")
        #expect(completed.response.status == "completed")
        #expect(completed.response.usage?.inputTokens == 100)
        #expect(completed.response.usage?.outputTokens == 50)
        #expect(completed.response.usage?.totalTokens == 150)
        #expect(completed.response.error == nil)
    }

    @Test("Parses response completed without model")
    func parseCompletedNoModel() throws {
        let json = """
        {
            "type": "response.completed",
            "response": {
                "id": "resp_456",
                "status": "completed"
            }
        }
        """
        let completed = try JSONDecoder().decode(ResponseCompleted.self, from: json.data(using: .utf8)!)

        #expect(completed.response.id == "resp_456")
        #expect(completed.response.model == nil)
        #expect(completed.response.usage == nil)
    }

    @Test("Parses response failed with error")
    func parseFailed() throws {
        let json = """
        {
            "type": "response.failed",
            "response": {
                "id": "resp_err",
                "status": "failed",
                "error": {
                    "code": "rate_limit",
                    "message": "Too many requests"
                }
            }
        }
        """
        let failed = try JSONDecoder().decode(ResponseCompleted.self, from: json.data(using: .utf8)!)

        #expect(failed.response.status == "failed")
        #expect(failed.response.error?.code == "rate_limit")
        #expect(failed.response.error?.message == "Too many requests")
    }

    // MARK: - AgentStreamEvent

    @Test("AgentStreamEvent textDelta carries content")
    func streamEventTextDelta() {
        let event = AgentStreamEvent.textDelta("Hello")
        if case .textDelta(let text) = event {
            #expect(text == "Hello")
        } else {
            Issue.record("Expected textDelta")
        }
    }

    @Test("AgentStreamEvent completed carries usage")
    func streamEventCompleted() {
        let usage = TokenUsage(inputTokens: 10, outputTokens: 20, totalTokens: 30)
        let event = AgentStreamEvent.completed(tokenUsage: usage, responseId: "resp_1")
        if case .completed(let u, let id) = event {
            #expect(u?.outputTokens == 20)
            #expect(id == "resp_1")
        } else {
            Issue.record("Expected completed")
        }
    }

    @Test("AgentStreamEvent completed with nil usage")
    func streamEventCompletedNil() {
        let event = AgentStreamEvent.completed(tokenUsage: nil, responseId: nil)
        if case .completed(let u, let id) = event {
            #expect(u == nil)
            #expect(id == nil)
        } else {
            Issue.record("Expected completed")
        }
    }

    @Test("AgentStreamEvent modelIdentified carries model string")
    func streamEventModelIdentified() {
        let event = AgentStreamEvent.modelIdentified("claude-opus")
        if case .modelIdentified(let model) = event {
            #expect(model == "claude-opus")
        } else {
            Issue.record("Expected modelIdentified")
        }
    }

    // MARK: - Request Building

    @Test("Chat Completions request encodes images as data URIs")
    func requestEncodesImages() throws {
        let fakeImage = Data([0xFF, 0xD8, 0xFF])
        let request = ChatCompletionRequest(
            model: "openclaw:main",
            messages: [
                .init(role: "user", content: .parts([
                    .text("What's this?"),
                    .imageURL("data:image/jpeg;base64,\(fakeImage.base64EncodedString())")
                ]))
            ],
            stream: true,
            user: nil
        )

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let messages = json["messages"] as! [[String: Any]]
        let content = messages[0]["content"] as! [[String: Any]]

        #expect(content.count == 2)
        #expect(content[0]["type"] as? String == "text")
        #expect(content[1]["type"] as? String == "image_url")
    }

    @Test("Open Responses request encodes images with base64 source")
    func openResponsesEncodesImages() throws {
        let request = OpenResponsesRequest(
            model: "openclaw:main",
            input: .items([
                .init(type: "message", role: "user", content: .parts([
                    .inputText("Describe this"),
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
        #expect(parts[0]["type"] as? String == "input_text")
        #expect(parts[1]["type"] as? String == "input_image")

        let source = parts[1]["source"] as! [String: String]
        #expect(source["type"] == "base64")
        #expect(source["media_type"] == "image/jpeg")
    }
}
