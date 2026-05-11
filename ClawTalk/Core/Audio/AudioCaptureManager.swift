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
    // Back to 0.02 (original working value). Lowering it to 0.008
    // turned out to be a mistake — the sim's room-tone floor sits
    // around 0.012 and was registering as "speech" continuously,
    // keeping lastSpeechTime refreshed forever and preventing the
    // 1.5s silence timeout from ever firing. The earlier "hang" we
    // attributed to AGC suppression was actually the asymmetric
    // hasSpeechStarted state machine, fixed in 019b1b2.
    private let speechThreshold: Float = 0.02
    private let interruptThreshold: Float = 0.08
    /// Time of silence after detected speech before firing an utterance.
    /// 0.6s matches modern voice-mode apps (ChatGPT, Siri). Anything
    /// longer feels laggy after WhisperKit is warmed up; anything
    /// shorter risks cutting people off mid-comma.
    private let silenceDuration: TimeInterval = 0.6
    /// Fallback: if hasSpeechStarted but rms never crossed
    /// speechThreshold (e.g. iPhone voiceChat-mode AGC suppressed
    /// the user's speech below 0.02), force-fire the accumulated
    /// audio after this many seconds. WhisperKit can transcribe
    /// quiet audio that the simple rms VAD wouldn't catch.
    private let noSpeechForceFireTimeout: TimeInterval = 8.0
    private var listenStartedAt: Date?

    // Streaming mode (server-side STT via talk session)
    private(set) var isStreamingMode = false
    private var onAudioChunk: ((String) -> Void)?
    private var streamBuffer: [Float] = []
    /// Target ~100ms chunks at 24kHz = 2400 samples.
    private let streamChunkSamples = 2400
    /// Resampler from input rate to 24kHz pcm16 (built lazily on first chunk).
    private var streamConverter: AVAudioConverter?
    private var streamInputFormat: AVAudioFormat?
    private static let streamSampleRate: Double = 24000

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
        // Enable echo cancellation for conversation mode
        try? AVAudioSession.sharedInstance().setMode(.voiceChat)

        isContinuousMode = true
        self.onUtteranceDetected = onUtterance
        self.onInterrupt = onInterrupt
        utteranceSamples = []
        samples = []
        hasSpeechStarted = true
        lastSpeechTime = nil
        listenStartTime = nil
        listenStartedAt = Date()
        hasInterrupted = false
        isListening = true
        log.info("enableVAD: hasSpeechStarted=true, lastSpeechTime=nil")
    }

    /// Resume listening for the next utterance (after TTS finishes).
    /// Same shape as enableVAD: hasSpeechStarted=true so the silence
    /// timeout can fire, lastSpeechTime=nil so it doesn't fire until
    /// real speech. listenStartTime=Date() keeps the 800ms warmup
    /// that swallows the TTS echo tail.
    func resumeListening() {
        utteranceSamples = []
        hasSpeechStarted = true
        lastSpeechTime = nil
        listenStartTime = Date()
        listenStartedAt = Date()
        hasInterrupted = false
        isListening = true
    }

    /// Pause VAD collection (during TTS playback). Interrupt detection stays active.
    func pauseListening() {
        isListening = false
        utteranceSamples = []
        hasSpeechStarted = false
        lastSpeechTime = nil
        hasInterrupted = false
    }

    /// Fully stop conversation mode and tear down the engine.
    func stopContinuousRecording() {
        isContinuousMode = false
        isStreamingMode = false
        isListening = false
        onUtteranceDetected = nil
        onInterrupt = nil
        onAudioChunk = nil
        utteranceSamples = []
        streamBuffer = []
        streamConverter = nil
        streamInputFormat = nil
        hasSpeechStarted = false
        lastSpeechTime = nil
        hasInterrupted = false
        _ = stopEngine()
        try? AVAudioSession.sharedInstance().setMode(.default)
    }

    // MARK: - Streaming Mode (server-side STT)

    /// Switch a running engine to streaming mode. Emits ~100ms base64-encoded
    /// pcm16 chunks at 24kHz via `onChunk`. Local interrupt detection during
    /// playback stays active via `onInterrupt`. Call `pauseListening` /
    /// `resumeListening` to gate streaming during TTS playback.
    func enableStreaming(onChunk: @escaping (String) -> Void, onInterrupt: @escaping () -> Void) {
        try? AVAudioSession.sharedInstance().setMode(.voiceChat)

        isContinuousMode = true
        isStreamingMode = true
        onAudioChunk = onChunk
        self.onInterrupt = onInterrupt
        streamBuffer = []
        listenStartTime = nil
        hasInterrupted = false
        isListening = true
    }

    // MARK: - Engine

    private func startEngine() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
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

                let rms = sqrt(bufferSamples.reduce(0) { $0 + $1 * $1 } / Float(frameLength))
                self.currentLevel = rms

                if self.isStreamingMode {
                    self.processStreaming(bufferSamples, rms: rms, format: format)
                } else if self.isContinuousMode {
                    self.processVAD(bufferSamples, rms: rms)
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

    private func processVAD(_ bufferSamples: [Float], rms: Float) {
        // Tick log every ~50 buffers (~1s of audio) so we can see whether
        // the tap is firing at all and what the rms looks like.
        debugTickCount += 1
        if debugTickCount % 50 == 0 {
            log.info("VAD tick #\(self.debugTickCount): rms=\(String(format: "%.4f", rms)) listening=\(self.isListening) speech=\(self.hasSpeechStarted) hasLast=\(self.lastSpeechTime != nil) samples=\(self.utteranceSamples.count)")
        }

        if isListening {
            // Ignore first 800ms after resuming (TTS tail audio / echo)
            if let start = listenStartTime, Date().timeIntervalSince(start) < 0.8 {
                return
            }

            if rms > speechThreshold {
                if !hasSpeechStarted {
                    log.info("VAD: speech detected (rms=\(String(format: "%.4f", rms)))")
                }
                hasSpeechStarted = true
                lastSpeechTime = Date()
                utteranceSamples.append(contentsOf: bufferSamples)
            } else if hasSpeechStarted {
                utteranceSamples.append(contentsOf: bufferSamples)

                let normalFire = lastSpeechTime.map {
                    Date().timeIntervalSince($0) >= silenceDuration
                } ?? false
                // Force-fire only kicks in when rms never crossed the
                // speech threshold for the whole session (lastSpeechTime
                // is still nil). This catches iPhone voiceChat AGC
                // pulling speech below 0.02 — we'd hang forever
                // otherwise. Requires substantial buffer (~3s) so we
                // don't fire on a fraction of a second of room tone.
                let forceFire = lastSpeechTime == nil
                    && (listenStartedAt.map {
                        Date().timeIntervalSince($0) >= noSpeechForceFireTimeout
                    } ?? false)
                    && utteranceSamples.count > 144_000  // ~3s @ 48kHz

                if (normalFire || forceFire) && utteranceSamples.count > 8000 {
                    log.info("VAD: utterance fire (\(self.utteranceSamples.count) samples, force=\(forceFire))")
                    let captured = utteranceSamples
                    utteranceSamples = []
                    hasSpeechStarted = false
                    lastSpeechTime = nil
                    listenStartedAt = nil
                    isListening = false

                    let resampled = resampleTo16kHz(captured)
                    onUtteranceDetected?(resampled)
                }
            }
        } else if isContinuousMode && !hasInterrupted {
            // Not listening (TTS playing) - check for user interrupt
            if rms > interruptThreshold {
                hasInterrupted = true
                onInterrupt?()
            }
        }
    }

    // MARK: - Streaming

    private func processStreaming(_ bufferSamples: [Float], rms: Float, format: AVAudioFormat) {
        if isListening {
            if let start = listenStartTime, Date().timeIntervalSince(start) < 0.8 {
                // 800ms tail-skip after TTS resumes (echo guard)
                return
            }

            streamBuffer.append(contentsOf: bufferSamples)

            // Flush in ~100ms-of-output-audio-sized chunks.
            let inputRate = format.sampleRate
            let inputChunkSize = Int(inputRate * 0.1)
            while streamBuffer.count >= inputChunkSize {
                let chunk = Array(streamBuffer.prefix(inputChunkSize))
                streamBuffer.removeFirst(inputChunkSize)
                if let base64 = encodePCM16Base64(chunk, inputFormat: format) {
                    onAudioChunk?(base64)
                }
            }
        } else if !hasInterrupted {
            // Not listening (TTS playing) — local interrupt detection.
            if rms > interruptThreshold {
                hasInterrupted = true
                onInterrupt?()
            }
        }
    }

    /// Convert a Float chunk at the engine's native rate into 24kHz pcm16
    /// (signed 16-bit little-endian) bytes, base64-encoded.
    private func encodePCM16Base64(_ chunk: [Float], inputFormat: AVAudioFormat) -> String? {
        guard !chunk.isEmpty,
              let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: Self.streamSampleRate,
                channels: 1,
                interleaved: true
              ) else { return nil }

        // Cache the converter — engine format doesn't change mid-session.
        if streamConverter == nil || streamInputFormat?.sampleRate != inputFormat.sampleRate {
            streamConverter = AVAudioConverter(from: inputFormat, to: outputFormat)
            streamInputFormat = inputFormat
        }
        guard let converter = streamConverter,
              let inBuf = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(chunk.count)) else {
            return nil
        }
        inBuf.frameLength = AVAudioFrameCount(chunk.count)
        chunk.withUnsafeBufferPointer { ptr in
            inBuf.floatChannelData?[0].update(from: ptr.baseAddress!, count: chunk.count)
        }

        let outFrameCapacity = AVAudioFrameCount(Double(chunk.count) * Self.streamSampleRate / inputFormat.sampleRate + 1024)
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outFrameCapacity) else {
            return nil
        }

        var inputProvided = false
        var error: NSError?
        converter.convert(to: outBuf, error: &error) { _, status in
            if inputProvided {
                status.pointee = .noDataNow
                return nil
            }
            inputProvided = true
            status.pointee = .haveData
            return inBuf
        }
        if error != nil { return nil }

        let frameLength = Int(outBuf.frameLength)
        guard frameLength > 0, let int16Ptr = outBuf.int16ChannelData?[0] else { return nil }
        let byteCount = frameLength * MemoryLayout<Int16>.size
        let data = Data(bytes: int16Ptr, count: byteCount)
        return data.base64EncodedString()
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
