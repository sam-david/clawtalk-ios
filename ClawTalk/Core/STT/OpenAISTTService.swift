import Foundation
import AVFoundation

final class OpenAISTTService: TranscriptionService {
    private let apiKey: String
    private let session: URLSession

    init(apiKey: String) {
        self.apiKey = apiKey
        self.session = URLSession(configuration: .default)
    }

    func transcribe(audioSamples: [Float]) async throws -> String {
        let wavData = encodeWAV(samples: audioSamples, sampleRate: 16000)

        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        // File field
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
        body.append("Content-Type: audio/wav\r\n\r\n")
        body.append(wavData)
        body.append("\r\n")
        // Model field
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.append("gpt-4o-mini-transcribe\r\n")
        body.append("--\(boundary)--\r\n")

        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw OpenClawError.httpError(status)
        }

        struct TranscriptionResponse: Decodable { let text: String }
        let result = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return result.text
    }

    private func encodeWAV(samples: [Float], sampleRate: Int) -> Data {
        let numChannels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let byteRate = Int32(sampleRate * Int(numChannels) * Int(bitsPerSample / 8))
        let blockAlign = Int16(numChannels * (bitsPerSample / 8))
        let dataSize = Int32(samples.count * Int(bitsPerSample / 8))
        let chunkSize = 36 + dataSize

        var data = Data()
        data.append("RIFF")
        data.appendLittleEndian(chunkSize)
        data.append("WAVE")
        data.append("fmt ")
        data.appendLittleEndian(Int32(16)) // subchunk1 size
        data.appendLittleEndian(Int16(1))  // PCM format
        data.appendLittleEndian(numChannels)
        data.appendLittleEndian(Int32(sampleRate))
        data.appendLittleEndian(byteRate)
        data.appendLittleEndian(blockAlign)
        data.appendLittleEndian(bitsPerSample)
        data.append("data")
        data.appendLittleEndian(dataSize)

        // Convert Float32 [-1, 1] to Int16
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16 = Int16(clamped * Float(Int16.max))
            data.appendLittleEndian(int16)
        }

        return data
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }

    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var le = value.littleEndian
        append(Data(bytes: &le, count: MemoryLayout<T>.size))
    }
}
