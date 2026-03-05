import Foundation

protocol SpeechService {
    /// Stream synthesized audio chunks for the given text.
    /// Each Data element is a chunk of PCM audio (24kHz, mono, Float32).
    func streamSpeech(text: String) -> AsyncThrowingStream<Data, Error>

    /// Stop any in-progress speech playback.
    func stop()
}
