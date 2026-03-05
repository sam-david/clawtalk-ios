import Foundation
import WhisperKit

final class WhisperKitService: TranscriptionService {
    private var whisperKit: WhisperKit?
    private let modelSize: WhisperModelSize
    private(set) var isLoaded = false
    private(set) var loadingProgress: Double = 0

    init(modelSize: WhisperModelSize) {
        self.modelSize = modelSize
    }

    func loadModel() async throws {
        let config = WhisperKitConfig(
            model: modelSize.rawValue,
            verbose: false,
            prewarm: true
        )
        let kit = try await WhisperKit(config)
        whisperKit = kit
        isLoaded = true
    }

    func transcribe(audioSamples: [Float]) async throws -> String {
        guard let kit = whisperKit else {
            try await loadModel()
            return try await transcribe(audioSamples: audioSamples)
        }

        let result = try await kit.transcribe(audioArray: audioSamples)
        return result.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
