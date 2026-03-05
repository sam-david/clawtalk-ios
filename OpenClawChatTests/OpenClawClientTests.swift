import Testing
@testable import OpenClawChat

@Suite("OpenClaw Client")
struct OpenClawClientTests {
    @Test("Rejects plain HTTP URLs")
    func rejectsHTTP() async {
        let client = OpenClawClient()
        let messages = [Message(role: .user, content: "test")]

        var receivedError: Error?
        do {
            for try await _ in client.streamChat(
                messages: messages,
                gatewayURL: "http://insecure.example.com",
                token: "test"
            ) {
                // Should not get here
            }
        } catch {
            receivedError = error
        }

        #expect(receivedError is OpenClawError)
        if let err = receivedError as? OpenClawError {
            switch err {
            case .insecureConnection:
                break // expected
            default:
                Issue.record("Expected insecureConnection, got \(err)")
            }
        }
    }

    @Test("Rejects empty gateway URL")
    func rejectsEmptyURL() async {
        let client = OpenClawClient()
        let messages = [Message(role: .user, content: "test")]

        var receivedError: Error?
        do {
            for try await _ in client.streamChat(
                messages: messages,
                gatewayURL: "",
                token: "test"
            ) {}
        } catch {
            receivedError = error
        }

        #expect(receivedError != nil)
    }

    @Test("Error descriptions are user-friendly")
    func errorDescriptions() {
        let errors: [OpenClawError] = [
            .invalidURL,
            .invalidResponse,
            .httpError(401),
            .emptyResponse,
            .insecureConnection
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }
}
