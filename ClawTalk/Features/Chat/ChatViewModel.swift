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
    private var talkSessionId: String?
    private var talkEventSubId: UUID?
    private var talkEventTask: Task<Void, Never>?
    private var talkPartialTranscript: String = ""
    private var talkSessionReady: Bool = false
    /// When non-nil, the UI should render a one-time banner explaining
    /// that the gateway doesn't support server-side STT and we've
    /// auto-disabled the setting.
    var serverSTTUnsupportedNotice: String?

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

    func stopRecordingAndSend(images: [Data] = []) {
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

                await sendMessage(transcript, images: images.isEmpty ? nil : images)
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

        if settings.settings.useServerSideSTT, let gateway = gatewayConnection,
           gateway.connectionState == .connected {
            startTalkSessionConversation(gateway: gateway)
        } else {
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
    }

    /// Set up server-side STT path: subscribe → create session → stream audio.
    private func startTalkSessionConversation(gateway: GatewayConnection) {
        let (subId, stream) = gateway.subscribeTalkEvents()
        talkEventSubId = subId
        talkPartialTranscript = ""

        talkEventTask = Task { [weak self] in
            for await evt in stream {
                guard let self else { return }
                await MainActor.run { self.handleTalkEvent(evt) }
                if Task.isCancelled { break }
            }
        }

        Task {
            do {
                let result = try await gateway.talkSessionCreate(
                    sessionKey: sessionKey,
                    mode: .transcription,
                    transport: .gatewayRelay,
                    brain: TalkBrain.none
                )
                self.talkSessionId = result.sessionId
                // Audio capture stays in the default (non-streaming) path
                // until we receive a session.ready event. Without this, the
                // first audio chunks can arrive before the upstream STT
                // provider's session is fully open and get dropped, which
                // surfaces as a truncated first transcript.
                self.audioCapture.enableStreaming(
                    onChunk: { [weak self] base64 in
                        guard let self,
                              let sid = self.talkSessionId,
                              self.talkSessionReady else { return }
                        Task { @MainActor in
                            try? await gateway.talkSessionAppendAudio(sessionId: sid, audioBase64: base64)
                        }
                    },
                    onInterrupt: { [weak self] in
                        Task { @MainActor in
                            self?.handleConversationInterrupt()
                        }
                    }
                )
            } catch {
                if Self.isUnknownMethodError(error) {
                    // Gateway is too old to know this method at all. Flip the
                    // setting off so we don't keep retrying, and surface a
                    // one-time banner explaining what happened.
                    settings.settings.useServerSideSTT = false
                    settings.save()
                    serverSTTUnsupportedNotice = "Server-side STT isn't supported by your gateway. Turned the setting off; using on-device transcription instead."
                } else {
                    errorMessage = "Couldn't start talk session: \(error.localizedDescription). Falling back to on-device STT."
                }
                self.tearDownTalkSession()
                self.audioCapture.enableVAD(
                    onUtterance: { [weak self] samples in
                        Task { @MainActor in self?.handleConversationUtterance(samples) }
                    },
                    onInterrupt: { [weak self] in
                        Task { @MainActor in self?.handleConversationInterrupt() }
                    }
                )
            }
        }
    }

    private func handleTalkEvent(_ evt: TalkEventPayload) {
        switch evt.type {
        case .sessionReady:
            talkSessionReady = true
        case .transcriptDelta:
            if let text = evt.transcriptText {
                talkPartialTranscript += text
            }
        case .transcriptDone:
            let raw = evt.transcriptText ?? talkPartialTranscript
            let final = TranscriptCleanup.clean(raw)
            talkPartialTranscript = ""
            guard !final.isEmpty else { return }

            audioCapture.pauseListening()
            state = .transcribing
            sendTask = Task { await sendMessage(final) }
        case .sessionError:
            errorMessage = evt.errorMessage ?? "Talk session error"
        case .sessionClosed:
            talkSessionReady = false
        default:
            break
        }
    }

    private static func isUnknownMethodError(_ error: Error) -> Bool {
        guard case GatewayWebSocket.GatewayError.responseError(_, _, let msg) = error else {
            return false
        }
        return msg.lowercased().contains("unknown method")
    }

    private func tearDownTalkSession() {
        talkEventTask?.cancel()
        talkEventTask = nil
        if let id = talkEventSubId, let gateway = gatewayConnection {
            gateway.unsubscribeTalkEvents(id: id)
        }
        talkEventSubId = nil

        if let sid = talkSessionId, let gateway = gatewayConnection {
            Task { try? await gateway.talkSessionClose(sessionId: sid) }
        }
        talkSessionId = nil
        talkPartialTranscript = ""
        talkSessionReady = false
    }

    func exitConversationMode() {
        isConversationMode = false
        sendTask?.cancel()
        tearDownTalkSession()
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
        // Prefer cached device auth token from gateway, fall back to settings token.
        let resolvedToken = OpenClawClient.resolveHTTPToken(
            settingsToken: settings.gatewayToken,
            gatewayURL: settings.settings.gatewayURL
        )
        try await streamHTTP(token: resolvedToken, images: images)
    }

    /// Drive the HTTP streaming loop with the given token.
    /// On a 401, clears the stale device token and retries once with the settings token.
    private func streamHTTP(token: String, images: [Data]?, isRetry: Bool = false) async throws {
        // Send full conversation history — the gateway HTTP API does not
        // persist sessions between requests, so each call needs full context.
        let eventStream = openClaw.stream(
            messages: messages.filter { !$0.isStreaming },
            gatewayURL: settings.settings.gatewayURL,
            token: token,
            model: channel.modelString,
            apiMode: settings.settings.agentAPIMode,
            sessionKey: sessionKey,
            messageChannel: "webchat"
        )

        state = .streaming

        var fullResponse = ""
        var sentenceBuf = ""

        if settings.settings.voiceOutputEnabled, speechService != nil {
            try audioPlayback.start()
            if isConversationMode { audioCapture.pauseListening() }
            state = .speaking
        }

        do {
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
        } catch let error as OpenClawError where !isRetry {
            // On 401/403, clear stale device token and retry once with settings token
            if case .httpErrorDetailed(let code, _, _) = error, code == 401 || code == 403 {
                let identity = DeviceIdentityManager.loadOrCreate()
                let host = URL(string: settings.settings.gatewayURL)?.host ?? settings.settings.gatewayURL
                DeviceAuthTokenStore.clearToken(deviceId: identity.deviceId, role: "user", gatewayHost: host)
                fullResponse = ""
                if let idx = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
                    messages[idx].content = ""
                }
                try await streamHTTP(token: settings.gatewayToken, images: images, isRetry: true)
                return
            }
            if case .httpError(let code) = error, code == 401 || code == 403 {
                let identity = DeviceIdentityManager.loadOrCreate()
                let host = URL(string: settings.settings.gatewayURL)?.host ?? settings.settings.gatewayURL
                DeviceAuthTokenStore.clearToken(deviceId: identity.deviceId, role: "user", gatewayHost: host)
                fullResponse = ""
                if let idx = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
                    messages[idx].content = ""
                }
                try await streamHTTP(token: settings.gatewayToken, images: images, isRetry: true)
                return
            }
            throw error
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

                // Only populate from server when local is empty — never
                // overwrite local messages to prevent data loss.
                if messages.isEmpty {
                    messages = converted
                    conversationStore.save(messages, channelId: channel.id)
                }
            } catch {
                // Non-fatal — server may not have history for this session
            }
        }
    }

    // MARK: - Lifecycle

    func configure(transcription: (any TranscriptionService)?, speech: any SpeechService) {
        self.transcriptionService = transcription
        self.speechService = speech
    }

    func clearHistory() {
        messages.removeAll()
        conversationStore.clear(channelId: channel.id)
        channel.sessionVersion += 1
        channelStore?.update(channel)
    }

    /// Save the current conversation state without modifying the live messages array.
    func saveCurrentState() {
        conversationStore.save(messages, channelId: channel.id)
    }

    /// Stop all active audio and cancel any in-flight tasks.
    func stop() {
        abortCurrentRun()
        sendTask?.cancel()

        // Finalize any in-progress streaming message before saving
        if let idx = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
            messages[idx].isStreaming = false
            if messages[idx].content.isEmpty { messages.remove(at: idx) }
        }
        conversationStore.save(messages, channelId: channel.id)

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
        case .authenticationFailed: return true
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
                    return .authenticationFailed("Authentication failed. Try again or check your gateway token in Settings.")
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
