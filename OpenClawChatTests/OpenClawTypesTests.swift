import Testing
import Foundation
@testable import OpenClawChat

@Suite("OpenClaw API Types")
struct OpenClawTypesTests {
    @Test("ChatCompletionRequest encodes correctly")
    func requestEncoding() throws {
        let request = ChatCompletionRequest(
            model: "openclaw:main",
            messages: [
                .init(role: "user", content: "Hello")
            ],
            stream: true,
            user: "ios-test"
        )

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["model"] as? String == "openclaw:main")
        #expect(json["stream"] as? Bool == true)
        #expect(json["user"] as? String == "ios-test")

        let messages = json["messages"] as! [[String: String]]
        #expect(messages.count == 1)
        #expect(messages[0]["role"] == "user")
        #expect(messages[0]["content"] == "Hello")
    }

    @Test("ChatCompletionChunk decodes SSE delta")
    func chunkDecoding() throws {
        let json = """
        {"id":"chatcmpl-123","choices":[{"delta":{"content":"Hello"},"finish_reason":null}]}
        """

        let chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: json.data(using: .utf8)!)

        #expect(chunk.choices.count == 1)
        #expect(chunk.choices[0].delta?.content == "Hello")
        #expect(chunk.choices[0].finishReason == nil)
    }

    @Test("ChatCompletionChunk decodes finish reason")
    func chunkFinishReason() throws {
        let json = """
        {"id":"chatcmpl-123","choices":[{"delta":{},"finish_reason":"stop"}]}
        """

        let chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: json.data(using: .utf8)!)

        #expect(chunk.choices[0].finishReason == "stop")
    }

    @Test("ChatCompletionResponse decodes full response")
    func responseDecoding() throws {
        let json = """
        {
            "id": "chatcmpl-456",
            "choices": [{
                "message": {"role": "assistant", "content": "The weather is sunny."},
                "finish_reason": "stop"
            }]
        }
        """

        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: json.data(using: .utf8)!)

        #expect(response.id == "chatcmpl-456")
        #expect(response.choices[0].message.content == "The weather is sunny.")
        #expect(response.choices[0].finishReason == "stop")
    }
}
