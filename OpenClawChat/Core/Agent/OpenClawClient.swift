import Foundation
import os.log

private let logger = Logger(subsystem: "com.openclaw.clawtalk", category: "network")

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

    // MARK: - Unified Streaming

    /// Stream agent events using the configured API mode.
    /// If Open Responses returns a 404, automatically falls back to Chat Completions.
    func stream(
        messages: [Message],
        gatewayURL: String,
        token: String,
        model: String = "openclaw:main",
        apiMode: AgentAPIMode
    ) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        switch apiMode {
        case .chatCompletions:
            return streamChatEvents(messages: messages, gatewayURL: gatewayURL, token: token, model: model)
        case .openResponses:
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        let responseStream = streamResponse(
                            messages: messages, gatewayURL: gatewayURL, token: token, model: model
                        )
                        for try await event in responseStream {
                            continuation.yield(event)
                        }
                        continuation.finish()
                    } catch let error as OpenClawError {
                        if case .httpErrorDetailed(let code, _, _) = error, code == 404 {
                            logger.info("Open Responses returned 404, falling back to Chat Completions")
                            do {
                                let fallbackStream = streamChatEvents(
                                    messages: messages, gatewayURL: gatewayURL, token: token, model: model
                                )
                                for try await event in fallbackStream {
                                    continuation.yield(event)
                                }
                                continuation.finish()
                            } catch {
                                continuation.finish(throwing: error)
                            }
                        } else {
                            continuation.finish(throwing: error)
                        }
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }

                continuation.onTermination = { _ in
                    task.cancel()
                }
            }
        }
    }

    // MARK: - Chat Completions (legacy, wrapped as AgentStreamEvent)

    private func streamChatEvents(
        messages: [Message],
        gatewayURL: String,
        token: String,
        model: String
    ) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try buildRequest(messages: messages, gatewayURL: gatewayURL, token: token, model: model)
                    let (bytes, response) = try await session.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        throw OpenClawError.invalidResponse
                    }
                    guard (200...299).contains(http.statusCode) else {
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                            if errorBody.count > 500 { break }
                        }
                        let bodySize = request.httpBody?.count ?? 0
                        throw OpenClawError.httpErrorDetailed(http.statusCode, bodySize, errorBody)
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

                        continuation.yield(.textDelta(content))
                    }

                    continuation.yield(.completed(tokenUsage: nil, responseId: nil))
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

    // MARK: - Open Responses API

    private func streamResponse(
        messages: [Message],
        gatewayURL: String,
        token: String,
        model: String
    ) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try buildResponseRequest(
                        messages: messages, gatewayURL: gatewayURL, token: token, model: model
                    )
                    let (bytes, response) = try await session.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        throw OpenClawError.invalidResponse
                    }
                    guard (200...299).contains(http.statusCode) else {
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                            if errorBody.count > 500 { break }
                        }
                        let bodySize = request.httpBody?.count ?? 0
                        throw OpenClawError.httpErrorDetailed(http.statusCode, bodySize, errorBody)
                    }

                    var currentEventType: String?

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }

                        if line.hasPrefix("event: ") {
                            currentEventType = String(line.dropFirst(7))
                            continue
                        }

                        if line.hasPrefix("data: ") {
                            let payload = String(line.dropFirst(6))
                            guard let data = payload.data(using: .utf8) else { continue }

                            switch currentEventType {
                            case "response.output_text.delta":
                                if let delta = try? JSONDecoder().decode(ResponseTextDelta.self, from: data) {
                                    continuation.yield(.textDelta(delta.delta))
                                }

                            case "response.completed":
                                if let completed = try? JSONDecoder().decode(ResponseCompleted.self, from: data) {
                                    let usage = completed.response.usage.map {
                                        TokenUsage(
                                            inputTokens: $0.inputTokens,
                                            outputTokens: $0.outputTokens,
                                            totalTokens: $0.totalTokens
                                        )
                                    }
                                    continuation.yield(.completed(
                                        tokenUsage: usage,
                                        responseId: completed.response.id
                                    ))
                                }

                            case "response.failed":
                                if let failed = try? JSONDecoder().decode(ResponseCompleted.self, from: data) {
                                    let msg = failed.response.error?.message ?? "Response failed"
                                    throw OpenClawError.responseError(msg)
                                }

                            default:
                                break
                            }

                            currentEventType = nil
                            continue
                        }

                        if line.isEmpty {
                            currentEventType = nil
                        }
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

    /// Stream a chat completion response from the OpenClaw Gateway.
    func streamChat(
        messages: [Message],
        gatewayURL: String,
        token: String,
        model: String = "openclaw:main"
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try buildRequest(messages: messages, gatewayURL: gatewayURL, token: token, model: model)
                    let (bytes, response) = try await session.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        throw OpenClawError.invalidResponse
                    }
                    guard (200...299).contains(http.statusCode) else {
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                            if errorBody.count > 500 { break }
                        }
                        let bodySize = request.httpBody?.count ?? 0
                        throw OpenClawError.httpErrorDetailed(http.statusCode, bodySize, errorBody)
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

    private func buildResponseRequest(
        messages: [Message],
        gatewayURL: String,
        token: String,
        model: String
    ) throws -> URLRequest {
        let baseURL = gatewayURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard let url = URL(string: "\(baseURL)/v1/responses") else {
            throw OpenClawError.invalidURL
        }

        guard url.scheme == "https" else {
            throw OpenClawError.insecureConnection
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let lastUserIndex = messages.lastIndex(where: { $0.role == .user })

        let items = messages.enumerated().map { index, msg -> OpenResponsesRequest.Item in
            if index == lastUserIndex, msg.hasImages, let images = msg.imageData {
                var parts: [OpenResponsesRequest.ContentPart] = []
                if !msg.content.isEmpty {
                    parts.append(.inputText(msg.content))
                }
                for imageData in images {
                    let base64 = imageData.base64EncodedString()
                    parts.append(.inputImage(mediaType: "image/jpeg", base64Data: base64))
                }
                return .init(type: "message", role: msg.role.rawValue, content: .parts(parts))
            } else {
                let text = msg.hasImages && !msg.content.isEmpty
                    ? msg.content + " [image]"
                    : msg.hasImages ? "[image]" : msg.content
                return .init(type: "message", role: msg.role.rawValue, content: .text(text))
            }
        }

        let body = OpenResponsesRequest(
            model: model,
            input: .items(items),
            stream: true,
            user: deviceID
        )

        request.httpBody = try JSONEncoder().encode(body)
        if let size = request.httpBody?.count {
            logger.info("OpenResponses request body size: \(size) bytes (\(size / 1024)KB)")
        }
        return request
    }

    private func buildRequest(
        messages: [Message],
        gatewayURL: String,
        token: String,
        model: String = "openclaw:main",
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

        // Only include image data for the most recent user message to avoid huge payloads
        let lastUserIndex = messages.lastIndex(where: { $0.role == .user })

        let body = ChatCompletionRequest(
            model: model,
            messages: messages.enumerated().map { index, msg in
                if index == lastUserIndex, msg.hasImages, let images = msg.imageData {
                    var parts: [ChatCompletionRequest.ChatMessage.ContentPart] = []
                    for imageData in images {
                        let base64 = imageData.base64EncodedString()
                        let dataURI = "data:image/jpeg;base64,\(base64)"
                        parts.append(.imageURL(dataURI))
                    }
                    if !msg.content.isEmpty {
                        parts.insert(.text(msg.content), at: 0)
                    }
                    return .init(role: msg.role.rawValue, content: .parts(parts))
                } else {
                    let text = msg.hasImages && !msg.content.isEmpty
                        ? msg.content + " [image]"
                        : msg.hasImages ? "[image]" : msg.content
                    return .init(role: msg.role.rawValue, content: .text(text))
                }
            },
            stream: stream,
            user: deviceID
        )

        request.httpBody = try JSONEncoder().encode(body)
        if let size = request.httpBody?.count {
            logger.info("Request body size: \(size) bytes (\(size / 1024)KB)")
        }
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
    case httpErrorDetailed(Int, Int, String)
    case emptyResponse
    case insecureConnection
    case responseError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid gateway URL."
        case .invalidResponse: return "Invalid response from server."
        case .httpError(let code): return "Server returned HTTP \(code)."
        case .httpErrorDetailed(let code, let bodyKB, let resp):
            let respPreview = resp.prefix(200)
            return "HTTP \(code) (sent \(bodyKB/1024)KB): \(respPreview)"
        case .emptyResponse: return "Empty response from agent."
        case .insecureConnection: return "HTTPS is required. Plain HTTP connections are not allowed."
        case .responseError(let msg): return msg
        }
    }
}
