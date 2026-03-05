import AVFoundation

final class AudioPlaybackManager {
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
    private(set) var isPlaying = false

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
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

        player.scheduleBuffer(buffer)
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
        guard let player = playerNode else { return }
        while player.isPlaying {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
