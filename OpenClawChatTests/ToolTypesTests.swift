import Testing
import Foundation
@testable import OpenClawChat

@Suite("Tool Types")
struct ToolTypesTests {
    // MARK: - JSONValue

    @Test("JSONValue encodes string")
    func jsonValueString() throws {
        let value = JSONValue.string("hello")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == .string("hello"))
    }

    @Test("JSONValue encodes int")
    func jsonValueInt() throws {
        let value = JSONValue.int(42)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == .int(42))
    }

    @Test("JSONValue encodes bool")
    func jsonValueBool() throws {
        let value = JSONValue.bool(true)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == .bool(true))
    }

    @Test("JSONValue encodes null")
    func jsonValueNull() throws {
        let value = JSONValue.null
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == .null)
    }

    @Test("JSONValue encodes object")
    func jsonValueObject() throws {
        let value = JSONValue.object(["key": .string("value"), "num": .int(5)])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == value)
    }

    @Test("JSONValue encodes array")
    func jsonValueArray() throws {
        let value = JSONValue.array([.string("a"), .int(1), .bool(false)])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == value)
    }

    // MARK: - ToolInvokeRequest

    @Test("ToolInvokeRequest encodes correctly")
    func requestEncoding() throws {
        let request = ToolInvokeRequest(
            tool: "memory_search",
            action: nil,
            args: ["query": .string("test"), "maxResults": .int(10)],
            sessionKey: nil
        )

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["tool"] as? String == "memory_search")
        let args = json["args"] as? [String: Any]
        #expect(args?["query"] as? String == "test")
        #expect(args?["maxResults"] as? Int == 10)
    }

    @Test("ToolInvokeRequest with action encodes correctly")
    func requestWithAction() throws {
        let request = ToolInvokeRequest(
            tool: "browser",
            action: "screenshot",
            args: ["type": .string("jpeg")],
            sessionKey: nil
        )

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["tool"] as? String == "browser")
        #expect(json["action"] as? String == "screenshot")
    }

    // MARK: - ToolInvokeResponse

    @Test("Success response decodes")
    func successResponse() throws {
        let json = """
        {"ok": true, "result": {"count": 5, "sessions": []}}
        """
        let decoded = try JSONDecoder().decode(ToolInvokeResponse.self, from: json.data(using: .utf8)!)
        #expect(decoded.ok == true)
        #expect(decoded.error == nil)
    }

    @Test("Error response decodes")
    func errorResponse() throws {
        let json = """
        {"ok": false, "error": {"type": "tool_error", "message": "Tool not found"}}
        """
        let decoded = try JSONDecoder().decode(ToolInvokeResponse.self, from: json.data(using: .utf8)!)
        #expect(decoded.ok == false)
        #expect(decoded.error?.message == "Tool not found")
        #expect(decoded.error?.type == "tool_error")
    }

    // MARK: - Domain Types

    @Test("MemorySearchResults decodes")
    func memorySearchDecode() throws {
        let json = """
        {
            "results": [
                {
                    "path": "MEMORY.md",
                    "snippet": "Project overview...",
                    "score": 0.85,
                    "startLine": 1,
                    "endLine": 10,
                    "source": "memory"
                }
            ],
            "provider": "local",
            "model": "bge-m3"
        }
        """
        let decoded = try JSONDecoder().decode(MemorySearchResults.self, from: json.data(using: .utf8)!)
        #expect(decoded.results.count == 1)
        #expect(decoded.results[0].path == "MEMORY.md")
        #expect(decoded.results[0].score == 0.85)
        #expect(decoded.results[0].source == "memory")
        #expect(decoded.provider == "local")
    }

    @Test("MemoryGetResult decodes")
    func memoryGetDecode() throws {
        let json = """
        {"path": "MEMORY.md", "text": "# My Memory\\nSome content here"}
        """
        let decoded = try JSONDecoder().decode(MemoryGetResult.self, from: json.data(using: .utf8)!)
        #expect(decoded.path == "MEMORY.md")
        #expect(decoded.text.contains("My Memory"))
    }

    @Test("SessionsListResult decodes")
    func sessionsListDecode() throws {
        let json = """
        {
            "count": 2,
            "sessions": [
                {
                    "key": "agent:main:main",
                    "kind": "main",
                    "channel": "general",
                    "displayName": "Main Session",
                    "updatedAt": 1700000000000,
                    "contextTokens": 1500,
                    "totalTokens": 5000
                },
                {
                    "key": "agent:coder:main",
                    "kind": "group"
                }
            ]
        }
        """
        let decoded = try JSONDecoder().decode(SessionsListResult.self, from: json.data(using: .utf8)!)
        #expect(decoded.count == 2)
        #expect(decoded.sessions[0].key == "agent:main:main")
        #expect(decoded.sessions[0].kind == "main")
        #expect(decoded.sessions[0].contextTokens == 1500)
        #expect(decoded.sessions[1].kind == "group")
    }

    @Test("SessionEntry handles missing optional fields")
    func sessionEntryPartial() throws {
        let json = """
        {"key": "agent:test:main"}
        """
        let decoded = try JSONDecoder().decode(SessionEntry.self, from: json.data(using: .utf8)!)
        #expect(decoded.key == "agent:test:main")
        #expect(decoded.kind == nil)
        #expect(decoded.channel == nil)
        #expect(decoded.contextTokens == nil)
    }
}
