# OpenClaw Chat iOS - Architecture

## Overview

A native iOS app that provides a voice interface to your OpenClaw agent. Push-to-talk to speak, get streaming voice responses back. Works from anywhere via Tailscale.

## Architecture Decision: Direct vs Pipecat

**Decision: Direct (no Pipecat).**

Pipecat is a powerful framework for real-time conversational AI with interruptions, turn-taking, and VAD. But it requires running a Python server, adds WebRTC complexity, and pulls in heavy dependencies (WebRTC binary frameworks, transport layers). For a push-to-talk app where the user explicitly controls when they're speaking, that machinery is unnecessary.

The direct approach means:
- No intermediary server between the phone and OpenClaw
- Fewer failure points (no Python server to maintain)
- Simpler codebase (~3 core components instead of a distributed system)
- On-device STT means even the transcription step has no server dependency

If we later want full-duplex conversational mode with interruptions, Pipecat (with SmallWebRTC transport) remains an option to layer in.

---

## System Architecture

```
+----------------------------------------------------------+
|  iPhone                                                   |
|                                                           |
|  +-----------+     +-------------+     +---------------+  |
|  | AVAudio   | --> | WhisperKit  | --> | Transcript    |  |
|  | Engine    |     | (on-device) |     | (String)      |  |
|  | (mic)     |     | STT         |     |               |  |
|  +-----------+     +-------------+     +-------+-------+  |
|                                                |          |
|                                        HTTP POST (SSE)    |
|                                                |          |
|  +-----------+     +-------------+     +-------v-------+  |
|  | AVAudio   | <-- | TTS Client  | <-- | OpenClaw     |  |
|  | Engine    |     | (streaming) |     | API Client   |  |
|  | (speaker) |     |             |     |               |  |
|  +-----------+     +-------------+     +---------------+  |
+----------------------------------------------------------+
                             |
                      Tailscale / LAN
                             |
+----------------------------------------------------------+
|  Server (home machine, VPS, etc.)                        |
|                                                           |
|  +----------------------------------------------------+  |
|  | OpenClaw Gateway  ws://host:18789                   |  |
|  |                                                      |  |
|  |  POST /v1/chat/completions  (OpenAI-compat API)     |  |
|  |  - stream: true (SSE)                                |  |
|  |  - model: "openclaw:main"                            |  |
|  |  - Authorization: Bearer <token>                     |  |
|  +----------------------------------------------------+  |
+----------------------------------------------------------+
```

---

## Component Stack

### 1. Speech-to-Text: WhisperKit (on-device)

**Package:** `github.com/argmaxinc/WhisperKit`
**Model:** `large-v3-turbo` (~1.6 GB, downloaded on first launch) or `small.en` (~250 MB) for storage-constrained devices

| Property | Value |
|----------|-------|
| Latency | ~0.5s for typical PTT clips |
| Cost | Free (on-device) |
| Offline | Yes |
| Accuracy | Matches cloud APIs (2.2% WER) |
| Platform | iOS 16+, Apple Neural Engine optimized |

**Flow:**
1. User presses and holds the talk button
2. `AVAudioEngine` captures PCM audio into a buffer
3. User releases the button
4. Buffer is fed directly to WhisperKit (no file I/O needed)
5. Transcript returned in ~0.5s

**Fallback:** OpenAI `gpt-4o-mini-transcribe` API ($0.003/min) for older devices or if WhisperKit fails. Simple HTTP POST with audio file.

### 2. Agent Communication: OpenClaw OpenAI-Compatible HTTP API

**Endpoint:** `POST /v1/chat/completions`
**Protocol:** HTTP with Server-Sent Events (SSE) for streaming

This endpoint must be enabled in OpenClaw config:
```json
{
  "gateway": {
    "http": {
      "endpoints": {
        "chatCompletions": {
          "enabled": true
        }
      }
    }
  }
}
```

**Request format:**
```json
{
  "model": "openclaw:main",
  "messages": [
    {"role": "user", "content": "What's the weather in Tokyo?"}
  ],
  "stream": true,
  "user": "ios-app-session-<device-id>"
}
```

**Response:** Standard OpenAI SSE stream (`data: {"choices":[{"delta":{"content":"..."}}]}`) terminated by `data: [DONE]`.

**Session persistence:** The `"user"` field maintains conversation continuity across requests. Use a stable device identifier.

**Authentication:** `Authorization: Bearer <OPENCLAW_GATEWAY_TOKEN>`

### 3. Text-to-Speech: Configurable (ElevenLabs or OpenAI)

Support both, let the user choose in settings.

#### Option A: ElevenLabs Streaming TTS

**Endpoint:** `POST https://api.elevenlabs.io/v1/text-to-speech/{voice_id}/stream`
**Output format:** `pcm_24000` (raw PCM for lowest latency playback)
**Model:** `eleven_flash_v2_5` (~75ms generation latency)

| Property | Value |
|----------|-------|
| Quality | Best-in-class naturalness |
| Latency | ~150-300ms time-to-first-audio (including network) |
| Cost | ~$0.10-0.15 per typical AI response (~500 chars) |
| Free tier | 10,000 chars/month (~10 min of speech) |

**Streaming playback:** As PCM chunks arrive via HTTP chunked transfer, feed them directly into `AVAudioPlayerNode` on an `AVAudioEngine` graph. Audio starts playing before the full response has been synthesized.

**For even lower latency with streaming LLM responses:** Use the WebSocket API (`wss://api.elevenlabs.io/v1/text-to-speech/{voice_id}/stream-input`) to push text chunks as they arrive from OpenClaw's SSE stream. This pipelines LLM generation and TTS generation.

#### Option B: OpenAI TTS

**Endpoint:** `POST https://api.openai.com/v1/audio/speech`
**Model:** `gpt-4o-mini-tts`

| Property | Value |
|----------|-------|
| Quality | Good (slightly less natural than ElevenLabs) |
| Latency | ~200-500ms |
| Cost | ~100x cheaper than ElevenLabs |
| Free tier | None (pay-per-use) |

Good default for cost-conscious usage. Can also stream via chunked transfer encoding.

#### Option C: Apple AVSpeechSynthesizer (Offline Fallback)

Free, instant, works offline. Sounds robotic but serves as a fallback when there's no network for cloud TTS (the OpenClaw call already succeeded, e.g., over a local network, but the TTS cloud API is unreachable).

### 4. Networking: Tailscale

The OpenClaw Gateway binds to localhost by default. To reach it from a phone on any network:

- Install Tailscale on the server running OpenClaw and on the iPhone
- Configure OpenClaw with Tailscale Serve or direct tailnet bind
- The app connects to `https://hostname.your-tailnet.ts.net`
- Encrypted, authenticated, works through NATs and firewalls
- No port forwarding or public exposure needed

Alternative: SSH tunnel for more technical users.

---

## App Architecture

### SwiftUI + MVVM

```
OpenClawChat/
  App/
    OpenClawChatApp.swift          # App entry point
    ContentView.swift              # Main view (conversation + talk button)

  Core/
    Audio/
      AudioCaptureManager.swift    # AVAudioEngine mic capture
      AudioPlaybackManager.swift   # AVAudioEngine + AVAudioPlayerNode streaming playback
    STT/
      TranscriptionService.swift   # Protocol
      WhisperKitService.swift      # On-device WhisperKit implementation
      OpenAISTTService.swift       # Cloud fallback implementation
    TTS/
      SpeechService.swift          # Protocol
      ElevenLabsTTSService.swift   # ElevenLabs streaming TTS
      OpenAITTSService.swift       # OpenAI TTS
      AppleTTSService.swift        # AVSpeechSynthesizer fallback
    Agent/
      OpenClawClient.swift         # HTTP client for OpenClaw API
      MessageStore.swift           # Conversation history (local)
      StreamingResponseParser.swift # SSE parser for streaming responses

  Features/
    Chat/
      ChatViewModel.swift          # Orchestrates the full STT -> Agent -> TTS flow
      ChatView.swift               # Conversation UI
      TalkButton.swift             # Push-to-talk button component
      MessageBubble.swift          # Chat message display
    Settings/
      SettingsView.swift           # Server URL, tokens, TTS provider, voice selection
      SettingsStore.swift          # UserDefaults / Keychain persistence

  Models/
    Message.swift                  # Chat message model
    AppSettings.swift              # Settings model
    OpenClawTypes.swift            # API request/response types
```

### Core Flow (ChatViewModel)

```
enum ChatState {
    case idle
    case recording          // User holding talk button
    case transcribing       // WhisperKit processing audio
    case thinking           // Waiting for OpenClaw first token
    case streaming          // Receiving + speaking OpenClaw response
}
```

**Push-to-talk flow:**
1. `idle` -> User presses button -> `recording`
   - Start `AVAudioEngine`, capture PCM into buffer
2. `recording` -> User releases button -> `transcribing`
   - Stop capture, feed buffer to WhisperKit
   - Display transcript in chat as user message
3. `transcribing` -> Transcript ready -> `thinking`
   - POST to OpenClaw `/v1/chat/completions` with `stream: true`
4. `thinking` -> First SSE token arrives -> `streaming`
   - Accumulate tokens into sentence-sized chunks
   - Pipeline chunks to TTS service
   - Play audio as PCM chunks arrive from TTS
   - Display text in chat as assistant message (live updating)
5. `streaming` -> SSE stream ends + audio playback finishes -> `idle`

### Streaming Pipeline (the key latency optimization)

The critical path is: **OpenClaw generates text** -> **TTS converts to audio** -> **user hears it**.

Rather than waiting for the full text response before starting TTS, we pipeline:

```
OpenClaw SSE:  |--token--token--token--|--token--token--.|
                        |                       |
Text buffer:   |---accumulate to sentence boundary---|
                        |                       |
TTS request:   |--chunk 1 POST--|  |--chunk 2 POST--|
                        |                       |
Audio play:    |====chunk 1 audio====|====chunk 2====|
```

**Sentence boundary detection:** Split on `.`, `!`, `?`, or after ~100 characters at the nearest word boundary. Each chunk becomes a separate TTS request, and audio chunks are queued for seamless sequential playback.

This means the user starts hearing the response ~1-2 seconds after OpenClaw begins generating, rather than waiting for the entire response.

---

## Dependencies

| Package | Purpose | Size Impact |
|---------|---------|-------------|
| `WhisperKit` (argmaxinc) | On-device STT | ~5 MB code + 250MB-1.6GB model (downloaded) |
| `KeychainAccess` (kishikawakatsumi) | Secure token storage | Minimal |

That's it. No WebRTC, no LiveKit, no Pipecat. The TTS and OpenClaw clients are simple HTTP — just `URLSession`.

---

## Configuration & Settings

The app needs these user-configurable values:

| Setting | Storage | Example |
|---------|---------|---------|
| OpenClaw Gateway URL | Keychain | `https://mybox.tail1234.ts.net` |
| OpenClaw Token | Keychain | `my-secret-token` |
| TTS Provider | UserDefaults | `elevenlabs` / `openai` / `apple` |
| ElevenLabs API Key | Keychain | `xi-...` |
| ElevenLabs Voice ID | UserDefaults | `21m00Tcm4TlvDq8ikWAM` |
| OpenAI API Key | Keychain | `sk-...` |
| OpenAI Voice | UserDefaults | `alloy` / `nova` / `shimmer` |
| Whisper Model Size | UserDefaults | `large-v3-turbo` / `small.en` |
| STT Fallback | UserDefaults | `enabled` / `disabled` |

---

## Future Considerations

- **Full-duplex conversation mode:** Add Pipecat with SmallWebRTC transport for hands-free, interruption-capable conversation. This would be a second "mode" alongside push-to-talk.
- **Apple SpeechAnalyzer (iOS 26):** When we can drop iOS <26 support, replace WhisperKit with Apple's built-in on-device STT. No model download needed.
- **Widgets / Live Activities:** Show agent status or last response on lock screen.
- **Apple Watch companion:** Quick voice queries from the wrist.
- **Shortcuts integration:** "Hey Siri, ask OpenClaw..." via App Intents.
- **Background audio:** Continue playing TTS response when app is backgrounded.
- **Conversation history sync:** Persist conversations and sync with OpenClaw's session memory.
