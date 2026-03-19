import Foundation
import os.log

private let logger = Logger(subsystem: "com.openclaw.clawtalk", category: "network")

final class OpenClawClient {
    private let session: URLSession
    let deviceID: String

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
        apiMode: AgentAPIMode,
        sessionKey: String? = nil,
        messageChannel: String? = nil
    ) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        switch apiMode {
        case .chatCompletions:
            return streamChatEvents(messages: messages, gatewayURL: gatewayURL, token: token, model: model, sessionKey: sessionKey, messageChannel: messageChannel)
        case .openResponses:
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        let responseStream = streamResponse(
                            messages: messages, gatewayURL: gatewayURL, token: token, model: model, sessionKey: sessionKey, messageChannel: messageChannel
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
                                    messages: messages, gatewayURL: gatewayURL, token: token, model: model, sessionKey: sessionKey, messageChannel: messageChannel
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
        model: String,
        sessionKey: String? = nil,
        messageChannel: String? = nil
    ) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try buildRequest(messages: messages, gatewayURL: gatewayURL, token: token, model: model, sessionKey: sessionKey, messageChannel: messageChannel)
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

                    var modelEmitted = false
                    var lastUsage: TokenUsage?
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }

                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))

                        if payload == "[DONE]" { break }

                        guard let data = payload.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: data) else {
                            continue
                        }

                        if !modelEmitted, let model = chunk.model, !model.isEmpty {
                            continuation.yield(.modelIdentified(model))
                            modelEmitted = true
                        }

                        if let content = chunk.choices.first?.delta?.content {
                            continuation.yield(.textDelta(content))
                        }

                        if let u = chunk.usage {
                            lastUsage = TokenUsage(
                                inputTokens: u.promptTokens ?? 0,
                                outputTokens: u.completionTokens ?? 0,
                                totalTokens: u.totalTokens ?? 0
                            )
                        }
                    }

                    continuation.yield(.completed(tokenUsage: lastUsage, responseId: nil))
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
        model: String,
        sessionKey: String? = nil,
        messageChannel: String? = nil
    ) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try buildResponseRequest(
                        messages: messages, gatewayURL: gatewayURL, token: token, model: model, sessionKey: sessionKey, messageChannel: messageChannel
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
                                    if let model = completed.response.model, !model.isEmpty {
                                        continuation.yield(.modelIdentified(model))
                                    }
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
        model: String,
        sessionKey: String? = nil,
        messageChannel: String? = nil
    ) throws -> URLRequest {
        let baseURL = gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard let url = URL(string: "\(baseURL)/v1/responses") else {
            throw OpenClawError.invalidURL
        }

        try requireSecureConnection(url)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let sessionKey { request.setValue(sessionKey, forHTTPHeaderField: "x-openclaw-session-key") }
        if let messageChannel { request.setValue(messageChannel, forHTTPHeaderField: "x-openclaw-message-channel") }

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
        stream: Bool = true,
        sessionKey: String? = nil,
        messageChannel: String? = nil
    ) throws -> URLRequest {
        let baseURL = gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            throw OpenClawError.invalidURL
        }

        try requireSecureConnection(url)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let sessionKey { request.setValue(sessionKey, forHTTPHeaderField: "x-openclaw-session-key") }
        if let messageChannel { request.setValue(messageChannel, forHTTPHeaderField: "x-openclaw-message-channel") }

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

    // MARK: - Tool Invocation

    /// Invoke a tool directly via POST /tools/invoke.
    /// Returns the raw result JSON Data for caller to decode into domain types.
    func invokeTool(
        tool: String,
        action: String? = nil,
        args: [String: JSONValue]? = nil,
        sessionKey: String? = nil,
        gatewayURL: String,
        token: String
    ) async throws -> Data {
        let baseURL = gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard let url = URL(string: "\(baseURL)/tools/invoke") else {
            throw OpenClawError.invalidURL
        }

        try requireSecureConnection(url)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let body = ToolInvokeRequest(
            tool: tool,
            action: action,
            args: args,
            sessionKey: sessionKey
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OpenClawError.invalidResponse
        }

        // Try to parse error body for both HTTP errors and {ok: false} responses
        if !((200...299).contains(http.statusCode)) {
            if let errorResponse = try? JSONDecoder().decode(ToolInvokeResponse.self, from: data),
               let errorType = errorResponse.error?.type,
               let msg = errorResponse.error?.message {
                if errorType == "not_found" {
                    throw OpenClawError.toolNotFound(tool)
                }
                throw OpenClawError.toolError(msg)
            }
            throw OpenClawError.httpError(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(ToolInvokeResponse.self, from: data)

        guard decoded.ok else {
            let msg = decoded.error?.message ?? "Tool invocation failed"
            throw OpenClawError.toolError(msg)
        }

        // Re-encode the result value as Data for domain-specific decoding
        guard let result = decoded.result else {
            return Data()
        }
        return try JSONEncoder().encode(result)
    }


    /// Check if a URL is secure enough for API calls.
    /// HTTPS is required for public hosts. HTTP is allowed for local/private network addresses.
    func requireSecureConnection(_ url: URL) throws {
        try Self.validateConnectionSecurity(url)
    }

    /// Static validation for testability. Throws `OpenClawError.insecureConnection` if the URL
    /// is plain HTTP to a non-local/non-private host.
    static func validateConnectionSecurity(_ url: URL) throws {
        if url.scheme == "https" { return }
        guard url.scheme == "http", let host = url.host?.lowercased() else {
            throw OpenClawError.insecureConnection
        }
        // Allow HTTP for local/private network addresses
        if host == "localhost" || host == "127.0.0.1" || host == "::1"
            || host.hasSuffix(".local")
            || host.hasPrefix("192.168.")
            || host.hasPrefix("10.")
            || host.hasPrefix("172.16.") || host.hasPrefix("172.17.") || host.hasPrefix("172.18.")
            || host.hasPrefix("172.19.") || host.hasPrefix("172.2") || host.hasPrefix("172.3")
        {
            return
        }
        throw OpenClawError.insecureConnection
    }

    /// Use the Ed25519 device identity as the stable device ID.
    /// This is the same identity used for WebSocket handshake signing,
    /// ensuring consistent identification across HTTP and WebSocket paths.
    private static func stableDeviceID() -> String {
        let identity = DeviceIdentityManager.loadOrCreate()
        return identity.deviceId
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
    case toolError(String)
    case toolNotFound(String)

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
        case .toolError(let msg): return msg
        case .toolNotFound(let name): return "Tool not available: \(name). Check your agent's tool configuration."
        }
    }
}
