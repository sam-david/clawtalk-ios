import Foundation
import AVFoundation

final class AppleTTSService: SpeechService {
    private let synthesizer = AVSpeechSynthesizer()

    func streamSpeech(text: String) -> AsyncThrowingStream<Data, Error> {
        // Apple's TTS doesn't stream PCM chunks via the same interface.
        // Instead, we use the synchronous speak() path.
        // Return an empty stream — playback is handled by AVSpeechSynthesizer directly.
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                let utterance = AVSpeechUtterance(string: text)
                utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
                utterance.rate = AVSpeechUtteranceDefaultSpeechRate
                self.synthesizer.speak(utterance)
                continuation.finish()
            }
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
