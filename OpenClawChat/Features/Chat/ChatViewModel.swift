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
    private var settings: SettingsStore
    private var channelStore: ChannelStore?
    private var transcriptionService: (any TranscriptionService)?
    private var speechService: (any SpeechService)?
    private var sendTask: Task<Void, Never>?
    private var recordingStart: Date?

    /// Stable session key for this channel, used for server-side session management.
    var sessionKey: String {
        let base = "agent:\(channel.agentId):clawtalk-user:\(openClaw.deviceID)"
        return channel.sessionVersion > 0 ? "\(base)-v\(channel.sessionVersion)" : base
    }

    init(settings: SettingsStore, channel: Channel, channelStore: ChannelStore? = nil) {
        self.settings = settings
        self.channel = channel
        self.channelStore = channelStore
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

        state = .thinking

        do {
            guard settings.isConfigured else {
                throw ChatError.notConfigured("Configure your OpenClaw gateway in Settings.")
            }

            let eventStream = openClaw.stream(
                messages: [userMessage],
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

            // Start audio playback engine if voice output is enabled
            if settings.settings.voiceOutputEnabled, speechService != nil {
                try audioPlayback.start()
                if isConversationMode {
                    audioCapture.pauseListening()
                }
                state = .speaking
            }

            for try await event in eventStream {
                try Task.checkCancellation()

                switch event {
                case .textDelta(let token):
                    fullResponse += token
                    sentenceBuf += token

                    // Update the assistant message in-place
                    if let idx = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
                        messages[idx].content = fullResponse
                    }

                    // Pipeline TTS: send sentence-sized chunks as they complete
                    if settings.settings.voiceOutputEnabled,
                       let tts = speechService,
                       let boundary = sentenceBuf.lastSentenceBoundary() {
                        let sentence = String(sentenceBuf.prefix(boundary))
                        sentenceBuf = String(sentenceBuf.dropFirst(boundary))

                        let audioStream = tts.streamSpeech(text: sentence)
                        for try await chunk in audioStream {
                            try Task.checkCancellation()
                            audioPlayback.enqueue(pcmData: chunk)
                        }
                    }

                case .completed(let tokenUsage, let responseId):
                    if let idx = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
                        messages[idx].tokenUsage = tokenUsage
                        messages[idx].responseId = responseId
                    }
                }
            }

            // Send any remaining text to TTS
            if settings.settings.voiceOutputEnabled,
               let tts = speechService,
               !sentenceBuf.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let audioStream = tts.streamSpeech(text: sentenceBuf)
                for try await chunk in audioStream {
                    try Task.checkCancellation()
                    audioPlayback.enqueue(pcmData: chunk)
                }
            }

            // Mark message as done streaming
            if let idx = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
                messages[idx].isStreaming = false
            }

            // Wait for audio to finish playing
            if settings.settings.voiceOutputEnabled {
                audioPlayback.markStreamingDone()
                await audioPlayback.waitUntilFinished()
                audioPlayback.stop()
            }

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
            if let idx = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
                messages[idx].isStreaming = false
                if messages[idx].content.isEmpty {
                    messages.remove(at: idx)
                }
            }
            audioPlayback.stop()
            errorMessage = error.localizedDescription

            if isConversationMode {
                audioCapture.resumeListening()
                state = .recording
            } else {
                state = .idle
            }
            conversationStore.save(messages, channelId: channel.id)
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

    func stopSpeaking() {
        speechService?.stop()
        audioPlayback.stop()
        if state == .speaking || state == .streaming {
            state = .idle
        }
    }

    var audioLevel: Float {
        audioCapture.currentLevel
    }
}

private enum ChatError: LocalizedError {
    case notConfigured(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let msg): return msg
        }
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
