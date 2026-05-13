import AVFoundation
import os.log

private let log = Logger(subsystem: "com.openclaw.clawtalk", category: "audio-capture")

final class AudioCaptureManager {
    private var audioEngine: AVAudioEngine?
    private var samples: [Float] = []
    private(set) var isRecording = false
    private(set) var currentLevel: Float = 0

    // Conversation mode VAD
    private(set) var isContinuousMode = false
    private var onUtteranceDetected: (([Float]) -> Void)?
    private var onInterrupt: (() -> Void)?
    private var utteranceSamples: [Float] = []
    private var hasSpeechStarted = false
    private var lastSpeechTime: Date?
    private var isListening = false
    private var listenStartTime: Date?
    private var hasInterrupted = false
    /// VAD operates on a smoothed RMS, not the per-buffer instantaneous
    /// value. Speech rms swings wildly between syllables — a single
    /// loud peak followed by a quiet trough looks like end-of-utterance
    /// to a naive threshold. Smoothing with a ~150ms time constant
    /// bridges those troughs so the threshold decision is stable.
    private var smoothedRms: Float = 0
    /// α for the EMA. At a 21ms buffer (1024 frames @ 48kHz), α=0.13
    /// is roughly a 150ms half-life — long enough to bridge syllables,
    /// short enough that end-of-utterance is detected promptly.
    private let smoothingAlpha: Float = 0.13
    /// Threshold on the smoothed rms. With voice processing enabled
    /// on the input node, speech smooths to ≈ 0.02–0.05 and background
    /// sits well under 0.01 on both sim and device, so 0.013 cleanly
    /// separates them.
    private let speechThreshold: Float = 0.013
    private let interruptThreshold: Float = 0.06
    /// Time of silence-after-speech (measured on smoothed rms) before
    /// firing an utterance.
    private let silenceDuration: TimeInterval = 0.9

    // MARK: - Push-to-Talk

    func startRecording() throws {
        isContinuousMode = false
        try startEngine()
    }

    func stopRecording() -> [Float] {
        if isContinuousMode { return [] }
        return stopEngine()
    }

    // MARK: - Conversation Mode

    /// Switch a running engine to VAD mode.
    ///
    /// hasSpeechStarted starts true so audio always accumulates into
    /// utteranceSamples — this is the only way the else-if branch of
    /// processVAD (which both appends buffers and runs the silence
    /// timeout) ever runs. lastSpeechTime starts nil so silence-only
    /// audio can't trigger a premature empty utterance — the fire
    /// check requires a non-nil lastSpeechTime, which only gets set
    /// once real speech crosses speechThreshold.
    func enableVAD(onUtterance: @escaping ([Float]) -> Void, onInterrupt: @escaping () -> Void) {
        isContinuousMode = true
        self.onUtteranceDetected = onUtterance
        self.onInterrupt = onInterrupt
        utteranceSamples = []
        samples = []
        smoothedRms = 0
        hasSpeechStarted = true
        lastSpeechTime = nil
        listenStartTime = nil
        hasInterrupted = false
        isListening = true
        log.info("enableVAD")
    }

    /// Resume listening for the next utterance (after TTS finishes).
    /// Same shape as enableVAD: hasSpeechStarted=true so the silence
    /// timeout can fire, lastSpeechTime=nil so it doesn't fire until
    /// real speech. listenStartTime=Date() keeps the 800ms warmup
    /// that swallows the TTS echo tail.
    func resumeListening() {
        utteranceSamples = []
        smoothedRms = 0
        hasSpeechStarted = true
        lastSpeechTime = nil
        listenStartTime = Date()
        hasInterrupted = false
        isListening = true
    }

    /// Pause VAD collection (during TTS playback). Interrupt detection stays active.
    func pauseListening() {
        isListening = false
        utteranceSamples = []
        smoothedRms = 0
        hasSpeechStarted = false
        lastSpeechTime = nil
        hasInterrupted = false
    }

    /// Fully stop conversation mode and tear down the engine.
    func stopContinuousRecording() {
        isContinuousMode = false
        isListening = false
        onUtteranceDetected = nil
        onInterrupt = nil
        utteranceSamples = []
        smoothedRms = 0
        hasSpeechStarted = false
        lastSpeechTime = nil
        hasInterrupted = false
        _ = stopEngine()
    }

    // MARK: - Engine

    private func startEngine() throws {
        let session = AVAudioSession.sharedInstance()
        // .voiceChat mode + voice processing on the input node give us
        // AEC, AGC, and noise suppression at the audio unit level —
        // the same path Zoom/FaceTime use. Speech rms ends up
        // normalized across devices (sim, iPhone, AirPods, external
        // mic), so a single threshold actually works.
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        do {
            try inputNode.setVoiceProcessingEnabled(true)
        } catch {
            log.error("voice processing unavailable: \(error.localizedDescription, privacy: .public)")
        }
        let format = inputNode.outputFormat(forBus: 0)

        samples = []
        smoothedRms = 0

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let channelData = buffer.floatChannelData?[0]
            let frameLength = Int(buffer.frameLength)

            if let channelData {
                let bufferSamples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))

                let instantRms = sqrt(bufferSamples.reduce(0) { $0 + $1 * $1 } / Float(frameLength))
                let α = self.smoothingAlpha
                self.smoothedRms = α * instantRms + (1 - α) * self.smoothedRms
                self.currentLevel = self.smoothedRms

                if self.isContinuousMode {
                    self.processVAD(bufferSamples, smoothedRms: self.smoothedRms)
                } else {
                    self.samples.append(contentsOf: bufferSamples)
                }
            }
        }

        engine.prepare()
        try engine.start()
        audioEngine = engine
        isRecording = true
    }

    private func stopEngine() -> [Float] {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isRecording = false
        currentLevel = 0

        let captured = samples
        samples = []
        return resampleTo16kHz(captured)
    }

    // MARK: - VAD

    private var debugTickCount = 0

    private func processVAD(_ bufferSamples: [Float], smoothedRms: Float) {
        // ~1Hz heartbeat. Strip before release.
        debugTickCount += 1
        if debugTickCount % 50 == 0 {
            log.info("VAD tick: rms=\(String(format: "%.4f", smoothedRms)) listening=\(self.isListening) speech=\(self.hasSpeechStarted) hasLast=\(self.lastSpeechTime != nil) samples=\(self.utteranceSamples.count)")
        }

        if isListening {
            // Ignore first 800ms after resuming (TTS tail audio / echo)
            if let start = listenStartTime, Date().timeIntervalSince(start) < 0.8 {
                return
            }

            if smoothedRms > speechThreshold {
                if lastSpeechTime == nil {
                    log.info("VAD: speech start (rms=\(String(format: "%.4f", smoothedRms)))")
                }
                hasSpeechStarted = true
                lastSpeechTime = Date()
                utteranceSamples.append(contentsOf: bufferSamples)
            } else if hasSpeechStarted {
                utteranceSamples.append(contentsOf: bufferSamples)

                let normalFire = lastSpeechTime.map {
                    Date().timeIntervalSince($0) >= silenceDuration
                } ?? false

                if normalFire && utteranceSamples.count > 8000 {
                    log.info("VAD fire: samples=\(self.utteranceSamples.count)")
                    let captured = utteranceSamples
                    utteranceSamples = []
                    hasSpeechStarted = false
                    lastSpeechTime = nil
                    isListening = false

                    let resampled = resampleTo16kHz(captured)
                    onUtteranceDetected?(resampled)
                }
            }
        } else if isContinuousMode && !hasInterrupted {
            // Not listening (TTS playing) - check for user interrupt
            if smoothedRms > interruptThreshold {
                hasInterrupted = true
                onInterrupt?()
            }
        }
    }

    // MARK: - Resampling

    private func resampleTo16kHz(_ captured: [Float]) -> [Float] {
        guard !captured.isEmpty else { return captured }

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
