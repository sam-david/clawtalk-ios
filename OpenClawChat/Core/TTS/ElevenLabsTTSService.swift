import Foundation

final class ElevenLabsTTSService: SpeechService {
    private let voiceID: String
    private let apiKey: String
    private let session: URLSession
    private var currentTask: Task<Void, Never>?

    init(voiceID: String, apiKey: String) {
        self.voiceID = voiceID
        self.apiKey = apiKey
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    func streamSpeech(text: String) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try buildRequest(text: text)
                    let (bytes, response) = try await session.bytes(for: request)

                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                        throw TTSError.httpError(status)
                    }

                    // ElevenLabs streams raw PCM bytes via chunked transfer encoding
                    var buffer = Data()
                    let chunkSize = 4800 // 100ms of audio at 24kHz mono Float32 (24000 * 4 / 10 / 2)

                    for try await byte in bytes {
                        if Task.isCancelled { break }
                        buffer.append(byte)

                        if buffer.count >= chunkSize {
                            continuation.yield(buffer)
                            buffer = Data()
                        }
                    }

                    // Flush remaining
                    if !buffer.isEmpty {
                        continuation.yield(buffer)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            currentTask = task
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func stop() {
        currentTask?.cancel()
        currentTask = nil
    }

    private func buildRequest(text: String) throws -> URLRequest {
        guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)/stream?output_format=pcm_24000") else {
            throw TTSError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_flash_v2_5",
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}

enum TTSError: LocalizedError {
    case httpError(Int)
    case invalidConfiguration

    var errorDescription: String? {
        switch self {
        case .httpError(let code): return "TTS service returned HTTP \(code)."
        case .invalidConfiguration: return "TTS is not configured. Check Settings."
        }
    }
}
