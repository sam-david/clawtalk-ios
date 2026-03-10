import Foundation
import Speech
import AVFoundation
import OSLog

/// On-device keyword detection using SFSpeechRecognizer.
/// The agent can configure wake words; when detected, a callback fires.
@Observable
@MainActor
final class VoiceWakeCapability {

    struct Config: Codable {
        var keywords: [String]
        var enabled: Bool
        var locale: String
    }

    struct ConfigResult: Encodable {
        let keywords: [String]
        let enabled: Bool
        let locale: String
    }

    enum VoiceWakeError: LocalizedError {
        case denied
        case unavailable
        case alreadyRunning

        var errorDescription: String? {
            switch self {
            case .denied: return "Speech recognition permission denied"
            case .unavailable: return "Speech recognition not available"
            case .alreadyRunning: return "Voice wake already running"
            }
        }
    }

    // MARK: - State

    private(set) var isListening = false
    private(set) var currentKeywords: [String] = []
    var onKeywordDetected: ((String) -> Void)?

    private let logger = Logger(subsystem: "com.openclaw.clawtalk", category: "voice-wake")
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?

    // MARK: - Singleton

    static let shared = VoiceWakeCapability()
    private init() {}

    // MARK: - Commands

    func setConfig(keywords: [String], enabled: Bool, locale: String?) async throws -> ConfigResult {
        currentKeywords = keywords

        if enabled && !keywords.isEmpty {
            try await startListening(locale: locale ?? "en-US")
        } else {
            stopListening()
        }

        return ConfigResult(
            keywords: currentKeywords,
            enabled: isListening,
            locale: locale ?? "en-US"
        )
    }

    func getConfig() -> ConfigResult {
        ConfigResult(
            keywords: currentKeywords,
            enabled: isListening,
            locale: recognizer?.locale.identifier ?? "en-US"
        )
    }

    // MARK: - Listening

    private func startListening(locale: String) async throws {
        guard !isListening else { throw VoiceWakeError.alreadyRunning }

        // Request speech recognition permission
        let authStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard authStatus == .authorized else { throw VoiceWakeError.denied }

        // Request microphone permission
        let micGranted = await AVAudioApplication.requestRecordPermission()
        guard micGranted else { throw VoiceWakeError.denied }

        guard let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)),
              speechRecognizer.isAvailable else {
            throw VoiceWakeError.unavailable
        }

        recognizer = speechRecognizer
        speechRecognizer.supportsOnDeviceRecognition = true

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        try engine.start()

        let lowercaseKeywords = currentKeywords.map { $0.lowercased() }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }

                if let result {
                    let text = result.bestTranscription.formattedString.lowercased()
                    for keyword in lowercaseKeywords {
                        if text.contains(keyword) {
                            self.logger.info("wake keyword detected: \(keyword, privacy: .public)")
                            self.onKeywordDetected?(keyword)
                            // Restart to clear buffer
                            self.stopListening()
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            try? await self.startListening(locale: locale)
                            return
                        }
                    }
                }

                if let error {
                    self.logger.error("voice wake error: \(error.localizedDescription, privacy: .public)")
                    self.stopListening()
                }
            }
        }

        audioEngine = engine
        recognitionRequest = request
        isListening = true
        logger.info("voice wake started, keywords: \(self.currentKeywords)")
    }

    func stopListening() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        logger.info("voice wake stopped")
    }
}

// MARK: - Params

struct VoiceWakeSetParams: Decodable {
    let keywords: [String]?
    let enabled: Bool?
    let locale: String?
}
