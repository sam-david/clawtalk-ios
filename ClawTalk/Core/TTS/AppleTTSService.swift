import Foundation
import AVFoundation

final class AppleTTSService: NSObject, SpeechService, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var completionHandler: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func streamSpeech(text: String) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                let utterance = AVSpeechUtterance(string: text)
                utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
                utterance.rate = AVSpeechUtteranceDefaultSpeechRate

                self.completionHandler = {
                    continuation.finish()
                }

                continuation.onTermination = { [weak self] _ in
                    self?.synthesizer.stopSpeaking(at: .immediate)
                    self?.completionHandler = nil
                }

                self.synthesizer.speak(utterance)
            }
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        completionHandler?()
        completionHandler = nil
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        completionHandler?()
        completionHandler = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        completionHandler?()
        completionHandler = nil
    }
}
