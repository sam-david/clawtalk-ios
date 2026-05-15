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

            let config = Self.resolveModelConfig(modelSize: modelSize)
            let kit = try await WhisperKit(config)
            let elapsed = ContinuousClock.now - start
            logger.info("WhisperKit: model ready in \(elapsed)")
            return kit
        }
    }

    /// Build a WhisperKitConfig pointing at the best available copy of the model:
    ///   1. (Debug only) A copy bundled inside the .app at install time, so
    ///      fresh dev rebuilds don't wait for the model to be downloaded
    ///      again. Gated on #if DEBUG so Release builds never bundle.
    ///   2. The user's previously-downloaded copy in Documents.
    ///   3. Fall through to WhisperKit's default download-on-first-use path.
    private static func resolveModelConfig(modelSize: WhisperModelSize) -> WhisperKitConfig {
        let modelName = "openai_whisper-\(modelSize.rawValue)"

        #if DEBUG
        if let resourcePath = Bundle.main.resourcePath {
            let bundled = URL(fileURLWithPath: resourcePath)
                .appendingPathComponent("whisperkit-coreml")
                .appendingPathComponent(modelName)
            if FileManager.default.fileExists(atPath: bundled.path) {
                logger.info("WhisperKit: using bundled Debug model at \(bundled.path)")
                return WhisperKitConfig(
                    modelFolder: bundled.path,
                    verbose: false,
                    prewarm: true,
                    load: true,
                    download: false
                )
            }
        }
        #endif

        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelDir = documentsURL.appendingPathComponent(
            "huggingface/models/argmaxinc/whisperkit-coreml/\(modelName)"
        )
        if FileManager.default.fileExists(atPath: modelDir.path) {
            logger.info("WhisperKit: using local model at \(modelDir.path)")
            return WhisperKitConfig(
                modelFolder: modelDir.path,
                verbose: false,
                prewarm: true,
                load: true,
                download: false
            )
        }

        return WhisperKitConfig(
            model: modelSize.rawValue,
            verbose: false,
            prewarm: true
        )
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
        let raw = result.map { $0.text }.joined(separator: " ")
        return TranscriptCleanup.clean(raw)
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
