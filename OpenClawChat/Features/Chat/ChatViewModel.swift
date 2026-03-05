import Foundation
import SwiftUI

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

    private let openClaw = OpenClawClient()
    private let audioCapture = AudioCaptureManager()
    private let audioPlayback = AudioPlaybackManager()
    private var settings: SettingsStore
    private var transcriptionService: (any TranscriptionService)?
    private var speechService: (any SpeechService)?
    private var currentStreamTask: Task<Void, Never>?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    // MARK: - Voice Input

    func startRecording() {
        guard state == .idle else { return }
        errorMessage = nil
        do {
            try audioCapture.startRecording()
            state = .recording
        } catch {
            errorMessage = "Microphone access failed: \(error.localizedDescription)"
        }
    }

    func stopRecordingAndSend() {
        guard state == .recording else { return }

        let samples = audioCapture.stopRecording()
        state = .transcribing

        Task {
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

    func sendText(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard state == .idle else { return }
        errorMessage = nil

        Task {
            await sendMessage(text)
        }
    }

    // MARK: - Core Send Flow

    private func sendMessage(_ content: String) async {
        let userMessage = Message(role: .user, content: content)
        messages.append(userMessage)

        var assistantMessage = Message(role: .assistant, content: "", isStreaming: true)
        messages.append(assistantMessage)

        state = .thinking

        do {
            guard settings.isConfigured else {
                throw ChatError.notConfigured("Configure your OpenClaw gateway in Settings.")
            }

            let stream = openClaw.streamChat(
                messages: messages.filter { !$0.isStreaming },
                gatewayURL: settings.settings.gatewayURL,
                token: settings.gatewayToken
            )

            state = .streaming

            var fullResponse = ""
            var sentenceBuf = ""

            // Start audio playback engine if voice output is enabled
            if settings.settings.voiceOutputEnabled, speechService != nil {
                try audioPlayback.start()
                state = .speaking
            }

            for try await token in stream {
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
                        audioPlayback.enqueue(pcmData: chunk)
                    }
                }
            }

            // Send any remaining text to TTS
            if settings.settings.voiceOutputEnabled,
               let tts = speechService,
               !sentenceBuf.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let audioStream = tts.streamSpeech(text: sentenceBuf)
                for try await chunk in audioStream {
                    audioPlayback.enqueue(pcmData: chunk)
                }
            }

            // Mark message as done streaming
            if let idx = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
                messages[idx].isStreaming = false
            }

            // Wait for audio to finish playing
            if settings.settings.voiceOutputEnabled {
                await audioPlayback.waitUntilFinished()
                audioPlayback.stop()
            }

            state = .idle

        } catch {
            if let idx = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
                messages[idx].isStreaming = false
                if messages[idx].content.isEmpty {
                    messages.remove(at: idx)
                }
            }
            audioPlayback.stop()
            errorMessage = error.localizedDescription
            state = .idle
        }
    }

    // MARK: - Lifecycle

    func configure(transcription: any TranscriptionService, speech: any SpeechService) {
        self.transcriptionService = transcription
        self.speechService = speech
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
