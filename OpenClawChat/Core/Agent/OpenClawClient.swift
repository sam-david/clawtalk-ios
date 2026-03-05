import Foundation

final class OpenClawClient {
    private let session: URLSession
    private let deviceID: String

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        // TLS 1.2 minimum enforced by default on iOS
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        self.session = URLSession(configuration: config)
        self.deviceID = Self.stableDeviceID()
    }

    /// Stream a chat completion response from the OpenClaw Gateway.
    func streamChat(
        messages: [Message],
        gatewayURL: String,
        token: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try buildRequest(messages: messages, gatewayURL: gatewayURL, token: token)
                    let (bytes, response) = try await session.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        throw OpenClawError.invalidResponse
                    }
                    guard (200...299).contains(http.statusCode) else {
                        throw OpenClawError.httpError(http.statusCode)
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }

                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))

                        if payload == "[DONE]" { break }

                        guard let data = payload.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: data),
                              let content = chunk.choices.first?.delta?.content else {
                            continue
                        }

                        continuation.yield(content)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Non-streaming chat completion.
    func chat(
        messages: [Message],
        gatewayURL: String,
        token: String
    ) async throws -> String {
        var request = try buildRequest(messages: messages, gatewayURL: gatewayURL, token: token, stream: false)
        request.timeoutInterval = 120

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw OpenClawError.httpError(status)
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw OpenClawError.emptyResponse
        }
        return content
    }

    private func buildRequest(
        messages: [Message],
        gatewayURL: String,
        token: String,
        stream: Bool = true
    ) throws -> URLRequest {
        let baseURL = gatewayURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            throw OpenClawError.invalidURL
        }

        guard url.scheme == "https" else {
            throw OpenClawError.insecureConnection
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body = ChatCompletionRequest(
            model: "openclaw:main",
            messages: messages.map {
                .init(role: $0.role.rawValue, content: $0.content)
            },
            stream: stream,
            user: deviceID
        )

        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private static func stableDeviceID() -> String {
        let key = "device_id"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let new = "ios-\(UUID().uuidString.prefix(8).lowercased())"
        UserDefaults.standard.set(new, forKey: key)
        return new
    }
}

enum OpenClawError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case emptyResponse
    case insecureConnection

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid gateway URL."
        case .invalidResponse: return "Invalid response from server."
        case .httpError(let code): return "Server returned HTTP \(code)."
        case .emptyResponse: return "Empty response from agent."
        case .insecureConnection: return "HTTPS is required. Plain HTTP connections are not allowed."
        }
    }
}
