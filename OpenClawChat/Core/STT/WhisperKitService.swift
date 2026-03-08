import Foundation
import WhisperKit
import os.log

private let logger = Logger(subsystem: "com.openclaw.clawtalk", category: "whisper")

final class WhisperKitService: TranscriptionService {
    private var whisperKit: WhisperKit?
    private let modelSize: WhisperModelSize
    private var loadTask: Task<WhisperKit, Error>?
    private(set) var isLoaded = false
    private(set) var loadingProgress: Double = 0

    init(modelSize: WhisperModelSize) {
        self.modelSize = modelSize
        // Eagerly start loading the model in the background
        self.loadTask = Task.detached(priority: .userInitiated) {
            let start = ContinuousClock.now
            logger.info("WhisperKit: loading model \(modelSize.rawValue)…")

            // Point at the already-downloaded model folder if it exists
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let modelDir = documentsURL.appendingPathComponent(
                "huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-\(modelSize.rawValue)"
            )
            let localExists = FileManager.default.fileExists(atPath: modelDir.path)

            let config: WhisperKitConfig
            if localExists {
                logger.info("WhisperKit: using local model at \(modelDir.path)")
                config = WhisperKitConfig(
                    modelFolder: modelDir.path,
                    verbose: false,
                    prewarm: true,
                    load: true,
                    download: false
                )
            } else {
                config = WhisperKitConfig(
                    model: modelSize.rawValue,
                    verbose: false,
                    prewarm: true
                )
            }

            let kit = try await WhisperKit(config)
            let elapsed = ContinuousClock.now - start
            logger.info("WhisperKit: model ready in \(elapsed)")
            return kit
        }
    }

    func transcribe(audioSamples: [Float]) async throws -> String {
        // Wait for the eagerly-started load if still in progress
        if whisperKit == nil, let loadTask {
            let kit = try await loadTask.value
            whisperKit = kit
            isLoaded = true
            self.loadTask = nil
        }

        guard let kit = whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        let result = try await kit.transcribe(audioArray: audioSamples)
        return result.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum TranscriptionError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "Whisper model failed to load. Check Settings."
        }
    }
}
