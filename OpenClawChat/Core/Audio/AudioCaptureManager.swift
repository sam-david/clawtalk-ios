import AVFoundation

final class AudioCaptureManager {
    private var audioEngine: AVAudioEngine?
    private var samples: [Float] = []
    private(set) var isRecording = false
    private(set) var currentLevel: Float = 0

    func startRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        samples = []

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let channelData = buffer.floatChannelData?[0]
            let frameLength = Int(buffer.frameLength)

            if let channelData {
                let bufferSamples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
                self.samples.append(contentsOf: bufferSamples)

                // RMS level for waveform visualization
                let rms = sqrt(bufferSamples.reduce(0) { $0 + $1 * $1 } / Float(frameLength))
                self.currentLevel = rms
            }
        }

        engine.prepare()
        try engine.start()
        audioEngine = engine
        isRecording = true
    }

    func stopRecording() -> [Float] {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isRecording = false
        currentLevel = 0

        let captured = samples

        // Resample to 16kHz mono if needed (WhisperKit expects 16kHz)
        let inputFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)
        let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)

        guard let inputFormat, let outputFormat,
              inputFormat.sampleRate != outputFormat.sampleRate,
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            return captured
        }

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let outputLength = Int(Double(captured.count) * ratio)
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(captured.count)),
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(outputLength)) else {
            return captured
        }

        inputBuffer.frameLength = AVAudioFrameCount(captured.count)
        captured.withUnsafeBufferPointer { ptr in
            inputBuffer.floatChannelData?[0].update(from: ptr.baseAddress!, count: captured.count)
        }

        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, status in
            status.pointee = .haveData
            return inputBuffer
        }

        if error != nil { return captured }

        let resampled = Array(UnsafeBufferPointer(
            start: outputBuffer.floatChannelData?[0],
            count: Int(outputBuffer.frameLength)
        ))
        return resampled
    }
}
