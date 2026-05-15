import AVFoundation

final class AudioPlaybackManager: @unchecked Sendable {
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
    private(set) var isPlaying = false
    private var buffersEnqueued = 0
    private var buffersCompleted = 0
    private var streamingDone = false

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        // Preserve .voiceChat if AudioCaptureManager already set it for
        // conversation mode — that mode's AEC is what stops TTS from
        // looping back through the mic loud enough to cross the
        // interrupt threshold and cancel the agent's response.
        let mode: AVAudioSession.Mode = (session.mode == .voiceChat) ? .voiceChat : .default
        try session.setCategory(.playAndRecord, mode: mode, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
        engine.prepare()
        try engine.start()

        player.play()
        audioEngine = engine
        playerNode = player
        isPlaying = true
        buffersEnqueued = 0
        buffersCompleted = 0
        streamingDone = false
    }

    /// Schedule a chunk of PCM audio (Float32, 24kHz, mono) for playback.
    func enqueue(pcmData: Data) {
        guard let player = playerNode else { return }

        let sampleCount = pcmData.count / MemoryLayout<Float>.size
        guard sampleCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: AVAudioFrameCount(sampleCount)) else {
            return
        }

        buffer.frameLength = AVAudioFrameCount(sampleCount)
        pcmData.withUnsafeBytes { raw in
            if let src = raw.baseAddress?.assumingMemoryBound(to: Float.self) {
                buffer.floatChannelData?[0].update(from: src, count: sampleCount)
            }
        }

        buffersEnqueued += 1
        player.scheduleBuffer(buffer) { [weak self] in
            self?.buffersCompleted += 1
        }
    }

    /// Signal that no more buffers will be enqueued.
    func markStreamingDone() {
        streamingDone = true
    }

    func stop() {
        playerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
        isPlaying = false
    }

    /// Wait until all enqueued audio has finished playing.
    func waitUntilFinished() async {
        guard buffersEnqueued > 0 else { return }
        // Wait until streaming is done and all buffers have completed
        while !streamingDone || buffersCompleted < buffersEnqueued {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        // Small grace period for audio output to flush
        try? await Task.sleep(nanoseconds: 200_000_000)
    }
}
