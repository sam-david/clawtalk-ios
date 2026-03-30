import Foundation

protocol TranscriptionService {
    /// Transcribe audio samples (PCM Float32, 16kHz mono) to text.
    func transcribe(audioSamples: [Float]) async throws -> String
}
