import Foundation
import SwiftUI
import UIKit

enum ChatState: Equatable {
    case idle
    case recording
    case transcribing
    case thinking
    case streaming
    case speaking
}

@Observable
@MainActor
final class ChatViewModel {
    var messages: [Message] = []
    var state: ChatState = .idle
    var errorMessage: String?
    var isConversationMode = false
    var channel: Channel
    private let openClaw = OpenClawClient()
    private let audioCapture = AudioCaptureManager()
    private let audioPlayback = AudioPlaybackManager()
    private let conversationStore = ConversationStore.shared
    private(set) var settings: SettingsStore
    private var channelStore: ChannelStore?
    private var gatewayConnection: GatewayConnection?
    private var transcriptionService: (any TranscriptionService)?
    private var speechService: (any SpeechService)?
    private var sendTask: Task<Void, Never>?
    private var recordingStart: Date?
    private var currentRunId: String?
    private var currentEventSubId: UUID?
    private var ttsStopped = false

    /// Stable session key for this channel, used for server-side session management.
    var sessionKey: String {
        let base = "agent:\(channel.agentId):clawtalk-user:\(openClaw.deviceID):\(channel.id.uuidString.prefix(8).lowercased())"
        return channel.sessionVersion > 0 ? "\(base)-v\(channel.sessionVersion)" : base
    }

    init(settings: SettingsStore, channel: Channel, channelStore: ChannelStore? = nil, gatewayConnection: GatewayConnection? = nil) {
        self.settings = settings
        self.channel = channel
        self.channelStore = channelStore
        self.gatewayConnection = gatewayConnection
        self.messages = conversationStore.load(channelId: channel.id)
    }

    // MARK: - Voice Input

    func startRecording() {
        guard state == .idle else { return }
        errorMessage = nil
        do {
            try audioCapture.startRecording()
            recordingStart = Date()
            state = .recording
        } catch {
            errorMessage = "Microphone access failed: \(error.localizedDescription)"
        }
    }

    func stopRecordingAndSend() {
        guard state == .recording else { return }
        if isConversationMode { return }

        let samples = audioCapture.stopRecording()

        // Ignore recordings shorter than 0.5s (accidental taps)
        let duration = Date().timeIntervalSince(recordingStart ?? Date())
        guard duration >= 0.5, samples.count > 8000 else {
            state = .idle
            return
        }

        state = .transcribing

        sendTask = Task {
            do {
                guard let stt = transcriptionService else {
                    throw ChatError.notConfigured("Speech-to-text not initialized")
                }

                let transcript = try await stt.transcribe(audioSamples: samples)
                guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    state = .idle
                    return
                }

                await sendMessage(transcript)
            } catch {
                errorMessage = "Transcription failed: \(error.localizedDescription)"
                state = .idle
            }
        }
    }

    // MARK: - Text Input

    func sendText(_ text: String, images: [Data] = []) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty else { return }
        guard state == .idle else { return }
        errorMessage = nil

        // Debug: /testimage sends a tiny red pixel to test image pipeline
        if text.trimmingCharacters(in: .whitespacesAndNewlines) == "/testimage" {
            let testImage = Self.makeTestImage()
            sendTask = Task {
                await sendMessage("What do you see in this image?", images: [testImage])
            }
            return
        }

        sendTask = Task {
            await sendMessage(text, images: images.isEmpty ? nil : images)
        }
    }

    private static func makeTestImage() -> Data {
        let size = CGSize(width: 100, height: 100)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            // Draw a simple white circle
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 25, y: 25, width: 50, height: 50))
        }
        return image.jpegData(compressionQuality: 0.8) ?? Data()
    }

    // MARK: - Conversation Mode

    func enterConversationMode() {
        guard state == .idle else { return }
        errorMessage = nil

        do {
            try audioCapture.startRecording()
            state = .recording
        } catch {
            errorMessage = "Microphone access failed: \(error.localizedDescription)"
            return
        }

        isConversationMode = true

        audioCapture.enableVAD(
            onUtterance: { [weak self] samples in
                Task { @MainActor in
                    self?.handleConversationUtterance(samples)
                }
            },
            onInterrupt: { [weak self] in
                Task { @MainActor in
                    self?.handleConversationInterrupt()
                }
            }
        )
    }

    func exitConversationMode() {
        isConversationMode = false
        sendTask?.cancel()
        audioCapture.stopContinuousRecording()
        speechService?.stop()
        audioPlayback.stop()

        if let idx = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
            messages[idx].isStreaming = false
        }

        state = .idle
        conversationStore.save(messages, channelId: channel.id)
    }

    private func handleConversationUtterance(_ samples: [Float]) {
        guard isConversationMode else { return }

        audioCapture.pauseListening()
        state = .transcribing

        sendTask = Task {
            do {
                guard let stt = transcriptionService else {
                    throw ChatError.notConfigured("Speech-to-text not initialized")
                }

                let transcript = try await stt.transcribe(audioSamples: samples)
                guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    if isConversationMode {
                        audioCapture.resumeListening()
                        state = .recording
                    }
                    return
                }

                await sendMessage(transcript)
            } catch is CancellationError {
                // Interrupted - don't change state
            } catch {
                errorMessage = "Transcription failed: \(error.localizedDescription)"
                if isConversationMode {
                    audioCapture.resumeListening()
                    state = .recording
                } else {
                    state = .idle
                }
            }
        }
    }

    private func handleConversationInterrupt() {
        guard isConversationMode else { return }
        guard state == .speaking || state == .streaming else { return }

        sendTask?.cancel()
        speechService?.stop()
        audioPlayback.stop()

        if let idx = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
            messages[idx].isStreaming = false
        }

        audioCapture.resumeListening()
        state = .recording
    }

    // MARK: - Core Send Flow

    private func sendMessage(_ content: String, images: [Data]? = nil) async {
        let userMessage = Message(role: .user, content: content, imageData: images)
        messages.append(userMessage)

        let assistantMessage = Message(role: .assistant, content: "", isStreaming: true)
        messages.append(assistantMessage)

        ttsStopped = false
        state = .thinking

        do {
            guard settings.isConfigured else {
                throw ChatError.notConfigured("Configure your OpenClaw gateway in Settings.")
            }

            if settings.settings.useWebSocket, let gateway = gatewayConnection,
               gateway.connectionState == .connected {
                do {
                    try await sendMessageViaWebSocket(content, images: images, gateway: gateway)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // WebSocket failed mid-stream — fall back to HTTP
                    // Remove the partial assistant message if empty
                    if let idx = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
                        if messages[idx].content.isEmpty {
                            messages.remove(at: idx)
                        } else {
                            // Keep partial response, don't retry
                            messages[idx].isStreaming = false
                            throw error
                        }
                    }
                    // Retry via HTTP
                    let retryAssistant = Message(role: .assistant, content: "", isStreaming: true)
                    messages.append(retryAssistant)
                    try await sendMessageViaHTTP(images: images)
                }
            } else {
                try await sendMessageViaHTTP(images: images)
            }

            notifySuccess()

            if isConversationMode {
                audioCapture.resumeListening()
                state = .recording
            } else {
                state = .idle
            }
            conversationStore.save(messages, channelId: channel.id)

        } catch is CancellationError {
            if let idx = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
                messages[idx].isStreaming = false
            }
            audioPlayback.stop()
            conversationStore.save(messages, channelId: channel.id)
        } catch {
            let classified = ChatError.classify(error)
            if let idx = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
                messages[idx].isStreaming = false
                if messages[idx].content.isEmpty {
                    messages.remove(at: idx)
                }
            }
            // Tag the user message with the error for retry
            if let userIdx = messages.lastIndex(where: { $0.role == .user }) {
                messages[userIdx].sendError = classified.errorDescription
            }
            audioPlayback.stop()
            errorMessage = classified.errorDescription
            notifyError()

            if isConversationMode {
                audioCapture.resumeListening()
                state = .recording
            } else {
                state = .idle
            }
            conversationStore.save(messages, channelId: channel.id)
        }
    }

    // MARK: - WebSocket Send Path

    private func sendMessageViaWebSocket(_ content: String, images: [Data]? = nil, gateway: GatewayConnection) async throws {
        // Subscribe to chat events BEFORE sending to avoid missing any
        let (subId, eventStream) = gateway.subscribeChatEvents()
        currentEventSubId = subId
        defer {
            gateway.unsubscribeChatEvents(id: subId)
            currentEventSubId = nil
            currentRunId = nil
        }

        let idempotencyKey = UUID().uuidString
        let response = try await gateway.chatSend(
            sessionKey: sessionKey,
            message: content,
            images: images,
            idempotencyKey: idempotencyKey
        )
        let runId = response.runId
        currentRunId = runId

        state = .streaming

        var fullResponse = ""
        var sentenceBuf = ""

        // Start audio playback engine if voice output is enabled
        if settings.settings.voiceOutputEnabled, speechService != nil {
            try audioPlayback.start()
            if isConversationMode { audioCapture.pauseListening() }
            state = .speaking
        }

        for await event in eventStream {
            try Task.checkCancellation()

            // Only handle events for our run
            guard event.runId == runId || event.runId == idempotencyKey else { continue }

            switch event.state {
            case "delta":
                if let text = event.message?.content?.first(where: { $0.type == "text" })?.text {
                    // The delta payload contains accumulated text, compute the new chunk
                    let delta: String
                    if text.count > fullResponse.count {
                        delta = String(text.dropFirst(fullResponse.count))
                    } else {
                        delta = text
                    }
                    fullResponse = text
                    sentenceBuf += delta

                    if let idx = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
                        messages[idx].content = fullResponse
                    }

                    // Pipeline TTS
                    if settings.settings.voiceOutputEnabled, !ttsStopped,
                       let tts = speechService,
                       let boundary = sentenceBuf.lastSentenceBoundary() {
                        let sentence = String(sentenceBuf.prefix(boundary))
                        sentenceBuf = String(sentenceBuf.dropFirst(boundary))
                        do {
                            let audioStream = tts.streamSpeech(text: sentence)
                            for try await chunk in audioStream {
                                guard !ttsStopped else { break }
                                try Task.checkCancellation()
                                audioPlayback.enqueue(pcmData: chunk)
                            }
                        } catch {
                            if !ttsStopped { throw error }
                        }
                    }
                }

            case "final":
                if let text = event.message?.content?.first(where: { $0.type == "text" })?.text {
                    fullResponse = text
                    if let idx = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
                        messages[idx].content = fullResponse
                    }
                }
                break // Exit the for-await loop after processing final

            case "error":
                let msg = event.errorMessage ?? "Agent error"
                throw ChatError.notConfigured(msg)

            default:
                continue
            }

            // Break after final
            if event.state == "final" { break }
        }

        // Flush remaining TTS
        try await flushRemainingTTS(sentenceBuf)

        // Mark done
        if let idx = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
            messages[idx].isStreaming = false
        }

        // Wait for audio (skip if user stopped TTS)
        if settings.settings.voiceOutputEnabled, !ttsStopped {
            audioPlayback.markStreamingDone()
            await audioPlayback.waitUntilFinished()
            audioPlayback.stop()
        }
    }

    // MARK: - HTTP Send Path

    private func sendMessageViaHTTP(images: [Data]? = nil) async throws {
        // Send full conversation history — the gateway HTTP API does not
        // persist sessions between requests, so each call needs full context.
        let eventStream = openClaw.stream(
            messages: messages.filter { !$0.isStreaming },
            gatewayURL: settings.settings.gatewayURL,
            token: settings.gatewayToken,
            model: channel.modelString,
            apiMode: settings.settings.agentAPIMode,
            sessionKey: sessionKey,
            messageChannel: "clawtalk"
        )

        state = .streaming

        var fullResponse = ""
        var sentenceBuf = ""

        if settings.settings.voiceOutputEnabled, speechService != nil {
            try audioPlayback.start()
            if isConversationMode { audioCapture.pauseListening() }
            state = .speaking
        }

        for try await event in eventStream {
            try Task.checkCancellation()

            switch event {
            case .textDelta(let token):
                fullResponse += token
                sentenceBuf += token

                if let idx = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
                    messages[idx].content = fullResponse
                }

                if settings.settings.voiceOutputEnabled, !ttsStopped,
                   let tts = speechService,
                   let boundary = sentenceBuf.lastSentenceBoundary() {
                    let sentence = String(sentenceBuf.prefix(boundary))
                    sentenceBuf = String(sentenceBuf.dropFirst(boundary))
                    do {
                        let audioStream = tts.streamSpeech(text: sentence)
                        for try await chunk in audioStream {
                            guard !ttsStopped else { break }
                            try Task.checkCancellation()
                            audioPlayback.enqueue(pcmData: chunk)
                        }
                    } catch {
                        if !ttsStopped { throw error }
                    }
                }

            case .modelIdentified(let model):
                if let idx = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
                    messages[idx].modelName = model
                }

            case .completed(let tokenUsage, let responseId):
                if let idx = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
                    messages[idx].tokenUsage = tokenUsage
                    messages[idx].responseId = responseId
                }
            }
        }

        try await flushRemainingTTS(sentenceBuf)

        if let idx = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
            messages[idx].isStreaming = false
        }

        if settings.settings.voiceOutputEnabled, !ttsStopped {
            audioPlayback.markStreamingDone()
            await audioPlayback.waitUntilFinished()
            audioPlayback.stop()
        }
    }

    // MARK: - TTS Helper

    private func flushRemainingTTS(_ sentenceBuf: String) async throws {
        if settings.settings.voiceOutputEnabled, !ttsStopped,
           let tts = speechService,
           !sentenceBuf.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                let audioStream = tts.streamSpeech(text: sentenceBuf)
                for try await chunk in audioStream {
                    guard !ttsStopped else { break }
                    try Task.checkCancellation()
                    audioPlayback.enqueue(pcmData: chunk)
                }
            } catch {
                if !ttsStopped { throw error }
            }
        }
    }

    // MARK: - Server History

    /// Load chat history from the server via WebSocket.
    /// Replaces local messages if the server has a session for this channel.
    func loadServerHistory() {
        guard settings.settings.useWebSocket,
              let gateway = gatewayConnection,
              gateway.connectionState == .connected
        else { return }

        Task {
            do {
                let history = try await gateway.chatHistory(sessionKey: sessionKey, limit: 100)
                guard let serverMessages = history.messages, !serverMessages.isEmpty else { return }

                let converted = serverMessages.compactMap { msg -> Message? in
                    guard let role = msg.role,
                          let messageRole = MessageRole(rawValue: role)
                    else { return nil }

                    let text: String
                    if let stringVal = msg.content?.stringValue {
                        text = stringVal
                    } else if let parts = msg.content?.arrayValue {
                        // Extract text from content parts array
                        text = parts.compactMap { part -> String? in
                            guard let dict = part.dictValue,
                                  dict["type"]?.stringValue == "text"
                            else { return nil }
                            return dict["text"]?.stringValue
                        }.joined()
                    } else {
                        return nil
                    }

                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                    return Message(role: messageRole, content: text)
                }

                guard !converted.isEmpty else { return }

                // Only replace if server has more/different messages
                if converted.count > messages.count || messages.isEmpty {
                    messages = converted
                    conversationStore.save(messages, channelId: channel.id)
                }
            } catch {
                // Non-fatal — server may not have history for this session
            }
        }
    }

    // MARK: - Lifecycle

    func configure(transcription: any TranscriptionService, speech: any SpeechService) {
        self.transcriptionService = transcription
        self.speechService = speech
    }

    func clearHistory() {
        messages.removeAll()
        conversationStore.clear(channelId: channel.id)
        channel.sessionVersion += 1
        channelStore?.update(channel)
    }

    /// Stop all active audio and cancel any in-flight tasks.
    func stop() {
        abortCurrentRun()
        sendTask?.cancel()
        if isConversationMode {
            isConversationMode = false
            audioCapture.stopContinuousRecording()
        } else if state == .recording {
            _ = audioCapture.stopRecording()
        }
        speechService?.stop()
        audioPlayback.stop()
        state = .idle
    }

    func stopSpeaking() {
        ttsStopped = true
        speechService?.stop()
        audioPlayback.stop()
        if state == .speaking {
            // Keep streaming text, just stop audio
            state = .streaming
        }
    }

    /// Send chat.abort for the current WebSocket run, if any.
    private func abortCurrentRun() {
        guard let runId = currentRunId,
              let gateway = gatewayConnection,
              gateway.connectionState == .connected
        else { return }

        let key = sessionKey
        // Clean up event subscription
        if let subId = currentEventSubId {
            gateway.unsubscribeChatEvents(id: subId)
            currentEventSubId = nil
        }
        currentRunId = nil

        Task {
            _ = try? await gateway.chatAbort(sessionKey: key, runId: runId)
        }
    }

    var audioLevel: Float {
        audioCapture.currentLevel
    }

    // MARK: - Message Management

    func deleteMessage(id: UUID) {
        messages.removeAll { $0.id == id }
        conversationStore.save(messages, channelId: channel.id)
    }

    /// Inject images from a node capability directly into the chat.
    func injectImages(_ images: [Data], caption: String?) {
        let message = Message(role: .assistant, content: caption ?? "", imageData: images)
        messages.append(message)
        conversationStore.save(messages, channelId: channel.id)
    }

    // MARK: - Retry

    /// Retry sending a failed user message.
    func retryMessage(id: UUID) {
        guard state == .idle else { return }
        guard let idx = messages.firstIndex(where: { $0.id == id && $0.role == .user && $0.hasFailed }) else { return }

        let content = messages[idx].content
        let images = messages[idx].imageData

        // Clear the error on the original message
        messages[idx].sendError = nil
        errorMessage = nil

        // Remove the original user message — sendMessage will re-add it
        messages.remove(at: idx)

        sendTask = Task {
            await sendMessage(content, images: images)
        }
    }

    // MARK: - Haptics

    private func notifySuccess() {
        guard settings.settings.hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func notifyError() {
        guard settings.settings.hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

enum ChatError: LocalizedError {
    case notConfigured(String)
    case authenticationFailed(String)
    case networkError(String)
    case serverError(Int, String)
    case agentError(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let msg): return msg
        case .authenticationFailed(let msg): return msg
        case .networkError(let msg): return msg
        case .serverError(let code, let msg): return "Server error (\(code)): \(msg)"
        case .agentError(let msg): return msg
        }
    }

    var isRetryable: Bool {
        switch self {
        case .notConfigured: return false
        case .authenticationFailed: return false
        case .networkError, .serverError, .agentError: return true
        }
    }

    /// Classify an error from OpenClawClient or URLSession into a ChatError.
    static func classify(_ error: Error) -> ChatError {
        if let openClawError = error as? OpenClawError {
            switch openClawError {
            case .httpError(let code), .httpErrorDetailed(let code, _, _):
                switch code {
                case 401, 403:
                    return .authenticationFailed("Authentication failed (HTTP \(code)). Check your gateway token in Settings.")
                case 408, 429:
                    return .networkError("Request timed out or rate limited. Try again.")
                case 400, 422:
                    return .agentError("Bad request. The agent couldn't process this message.")
                case 500...599:
                    return .serverError(code, "The gateway encountered an error. Try again.")
                default:
                    return .serverError(code, "Unexpected error from gateway.")
                }
            case .invalidURL:
                return .notConfigured("Invalid gateway URL. Check Settings.")
            case .insecureConnection:
                return .notConfigured("HTTPS is required. Update your gateway URL in Settings.")
            case .invalidResponse, .emptyResponse:
                return .agentError("Invalid or empty response from agent.")
            case .responseError(let msg):
                return .agentError(msg)
            case .toolError(let msg), .toolNotFound(let msg):
                return .agentError(msg)
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return .networkError("No internet connection.")
            case .timedOut:
                return .networkError("Connection timed out. Check your network and gateway.")
            case .cannotFindHost, .cannotConnectToHost:
                return .networkError("Cannot reach gateway. Check the URL and your network.")
            case .secureConnectionFailed:
                return .networkError("SSL/TLS connection failed.")
            case .cancelled:
                return .networkError("Request cancelled.")
            default:
                return .networkError(urlError.localizedDescription)
            }
        }

        if error is CancellationError {
            return .networkError("Cancelled")
        }

        return .agentError(error.localizedDescription)
    }
}

extension String {
    func lastSentenceBoundary() -> Int? {
        let terminators: [Character] = [".", "!", "?", "\n"]
        guard let lastIndex = self.lastIndex(where: { terminators.contains($0) }) else {
            // If buffer is long enough, break at a word boundary
            if self.count > 120, let spaceIdx = self.lastIndex(of: " ") {
                return self.distance(from: self.startIndex, to: self.index(after: spaceIdx))
            }
            return nil
        }
        let pos = self.distance(from: self.startIndex, to: self.index(after: lastIndex))
        return pos > 10 ? pos : nil // Don't send tiny fragments
    }
}
