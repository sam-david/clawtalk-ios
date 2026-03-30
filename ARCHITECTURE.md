# ClawTalk iOS - Architecture

## Overview

A native iOS app that provides voice and text chat with your OpenClaw agents. Push-to-talk, hands-free conversation mode with VAD, streaming text + TTS output, image sending, and multi-agent channels. Works from anywhere via Cloudflare Tunnel or Tailscale.

## Architecture Decision: Direct HTTP (No Pipecat)

**Decision: Direct HTTP to OpenClaw Gateway, no intermediary server.**

This means:
- No intermediary server between the phone and OpenClaw
- Fewer failure points (no Python server to maintain)
- Simpler codebase (~3 core components instead of a distributed system)
- On-device STT means even the transcription step has no server dependency

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
                  Cloudflare Tunnel / Tailscale
                             |
+----------------------------------------------------------+
|  Server (home machine, VPS, etc.)                        |
|                                                           |
|  +----------------------------------------------------+  |
|  | OpenClaw Gateway  :18789                            |  |
|  |                                                      |  |
|  |  POST /v1/chat/completions  (Chat Completions API)  |  |
|  |  POST /v1/responses         (Open Responses API)    |  |
|  |  - stream: true (SSE)                                |  |
|  |  - model: "openclaw:<agentId>"                       |  |
|  |  - Authorization: Bearer <token>                     |  |
|  +----------------------------------------------------+  |
+----------------------------------------------------------+
```

---

## Component Stack

### 1. Speech-to-Text: WhisperKit (on-device)

**Package:** `github.com/argmaxinc/WhisperKit`
**Models:** `small.en` (~250 MB, default) or `large-v3-turbo` (~1.6 GB, best quality)

| Property | Value |
|----------|-------|
| Latency | ~0.5s for typical PTT clips |
| Cost | Free (on-device) |
| Offline | Yes |
| Accuracy | Matches cloud APIs |
| Platform | iOS 17+, Apple Neural Engine optimized |

**Flow:**
1. User presses and holds the talk button
2. `AVAudioEngine` captures PCM audio into a buffer
3. User releases the button
4. Buffer is fed directly to WhisperKit
5. Transcript returned in ~0.5s

**Fallback:** OpenAI Whisper API for older devices or if WhisperKit fails.

### 2. Agent Communication: OpenClaw API

The app supports two API modes, configurable in Settings:

#### Chat Completions (default)
- **Endpoint:** `POST /v1/chat/completions`
- **Protocol:** HTTP with SSE (`data: <json>` lines, terminated by `data: [DONE]`)
- **Response types:** `ChatCompletionChunk` with `choices[0].delta.content`
- **Token usage:** Not available

#### Open Responses
- **Endpoint:** `POST /v1/responses`
- **Protocol:** HTTP with structured SSE (`event: <type>\ndata: <json>`)
- **Event types:** `response.output_text.delta`, `response.completed`, `response.failed`
- **Token usage:** Real input/output token counts from `response.completed`
- **Requires:** `gateway.http.endpoints.responses.enabled: true`

**Session headers:** Every request includes `x-openclaw-session-key` and `x-openclaw-message-channel: clawtalk` headers for routing and identification. Note that the gateway HTTP API does **not** persist sessions between requests — full conversation history is sent with each call. Server-side session management (with system prompt injection and context compaction) is only available through WebSocket/auto-reply flows (e.g., Telegram, Discord).

Both modes are abstracted behind a unified `AgentStreamEvent` enum:
```swift
enum AgentStreamEvent {
    case textDelta(String)
    case completed(tokenUsage: TokenUsage?, responseId: String?)
}
```

**Image support:** Up to 8 images per message (base64 JPEG). Both APIs support images — Chat Completions uses `image_url` content parts, Open Responses uses `input_image` with base64 source.

**Agent routing:** `"openclaw:<agentId>"` in the model field routes to specific agents.

### 3. Text-to-Speech: Configurable

Support all three, user chooses in Settings.

#### ElevenLabs (best quality)
- `POST /v1/text-to-speech/{voice_id}/stream`
- PCM streaming for lowest latency
- ~$0.10-0.15 per typical response
- Free tier: 10,000 chars/month

#### OpenAI TTS (cost-effective)
- `POST /v1/audio/speech`
- `gpt-4o-mini-tts` model
- ~100x cheaper than ElevenLabs

#### Apple AVSpeech (free, offline)
- Built-in `AVSpeechSynthesizer`
- Free and works offline, less natural
- Automatic fallback when cloud TTS API keys aren't configured

### 4. Networking

**Tailscale** (recommended): Install on server and phone, use `tailscale serve` for automatic HTTPS. Simplest setup — no DNS or tunnels required.

**Cloudflare Tunnel:** Alternative for a public-facing HTTPS URL without installing Tailscale on the phone.

The app enforces HTTPS-only connections.

---

## App Architecture

### SwiftUI + @Observable (MVVM)

```
ClawTalk/
  App/
    ClawTalkApp.swift          # App entry point, service wiring
    ContentView.swift              # Stub (unused, required by xcodegen)
    Theme.swift                    # Brand colors (openClawRed), markdown theme

  Core/
    Agent/
      OpenClawClient.swift         # HTTP client: Chat Completions + Open Responses
    Audio/
      AudioCaptureManager.swift    # AVAudioEngine mic capture + VAD
      AudioPlaybackManager.swift   # AVAudioEngine streaming playback
    STT/
      TranscriptionService.swift   # Protocol
      WhisperKitService.swift      # On-device WhisperKit implementation
      WhisperModelManager.swift    # Model download + progress tracking
      OpenAISTTService.swift       # Cloud fallback implementation
    TTS/
      SpeechService.swift          # Protocol
      ElevenLabsTTSService.swift   # ElevenLabs streaming TTS
      OpenAITTSService.swift       # OpenAI TTS
      AppleTTSService.swift        # AVSpeechSynthesizer fallback
    Security/
      SecureStorage.swift          # iOS Keychain wrapper (KeychainAccess)
    Storage/
      ChannelStore.swift           # Channel list persistence (UserDefaults)
      ConversationStore.swift      # Per-channel message persistence

  Features/
    Channels/
      ChannelListView.swift        # Channel list + add/delete
      AddChannelView.swift         # New channel creation with agent picker
    Chat/
      ChatViewModel.swift          # Orchestrates STT → Agent → TTS flow
      ChatView.swift               # Full chat UI (messages, input, voice)
      TalkButton.swift             # Push-to-talk / conversation mode button
      MessageBubble.swift          # Message display with markdown + token usage
    Settings/
      SettingsView.swift           # All app configuration
      SettingsStore.swift          # UserDefaults + Keychain persistence
    Setup/
      ModelDownloadView.swift      # WhisperKit model download progress
    Tools/
      ToolsView.swift              # Root tool category list with availability
      ToolsViewModel.swift         # @Observable VM for all tool calls
      MemorySearchView.swift       # Search + results list
      MemoryDetailView.swift       # Full memory file content
      AgentsView.swift             # Gateway agent list
      SessionsView.swift           # Session list + status + history
      BrowserView.swift            # Browser status, tabs, screenshots
      FileReadView.swift           # File path input + content display

  Models/
    AppSettings.swift              # Settings model + enums (TTSProvider, etc.)
    Channel.swift                  # Channel model (name, agentId, sessionVersion)
    Message.swift                  # Chat message (content, images, tokenUsage)
    ToolTypes.swift                # Tool request/response types, JSONValue
    OpenClawTypes.swift            # Chat Completions API types + shared types
    OpenResponsesTypes.swift       # Open Responses API types
```

### Core Flow (ChatViewModel)

```swift
enum ChatState {
    case idle
    case recording       // User holding talk button or conversation mode listening
    case transcribing    // WhisperKit processing audio
    case thinking        // Waiting for OpenClaw first token
    case streaming       // Receiving OpenClaw response
    case speaking        // TTS playing response audio
}
```

**Push-to-talk flow:**
1. `idle` → User holds button → `recording`
   - Start `AVAudioEngine`, capture PCM into buffer
2. `recording` → User releases button → `transcribing`
   - Stop capture, feed buffer to WhisperKit
   - Display transcript in chat as user message
3. `transcribing` → Transcript ready → `thinking`
   - POST to OpenClaw via unified `stream()` API
4. `thinking` → First SSE token arrives → `streaming`
   - Accumulate tokens into sentence-sized chunks
   - Pipeline chunks to TTS service
   - Display text in chat as assistant message (live updating)
5. `streaming` → SSE stream ends → `speaking`
   - TTS plays remaining queued audio
6. `speaking` → Audio playback finishes → `idle`

**Conversation mode flow:**
1. User taps (not holds) the talk button → enters conversation mode
2. After assistant finishes speaking, auto-listens for next user input (VAD)
3. Echo cancellation prevents the assistant's own audio from triggering recording
4. User can interrupt at any time by speaking
5. User taps "End" to exit conversation mode

**Text input flow:**
1. User taps keyboard icon → switches to text mode
2. User types message → taps send
3. Same `thinking` → `streaming` → `speaking` flow

### Tools Dashboard

The app provides direct access to agent tools via `POST /tools/invoke`:

```swift
// OpenClawClient.invokeTool()
func invokeTool(tool:, action:, args:, sessionKey:, gatewayURL:, token:) async throws -> Data
```

**Supported tools:** `memory_search`, `memory_get`, `agents_list`, `sessions_list`, `session_status`, `session_history`, `browser` (status/screenshot/tabs), `read` (files)

**Availability probing:** On each Tools view appearance, the app probes all tool categories in parallel via `withTaskGroup`. Each probe makes a lightweight call and checks for `toolNotFound` errors. Unavailable tools are shown greyed out.

**Tool profiles** control which tools an agent can access: `minimal`, `coding`, `messaging`, `full`. Memory tools additionally require an embedding provider. File read requires the `coding` profile.

### Streaming Pipeline

The critical latency optimization pipelines LLM generation with TTS:

```
OpenClaw SSE:  |--token--token--token--|--token--token--.|
                        |                       |
Text buffer:   |---accumulate to sentence boundary---|
                        |                       |
TTS request:   |--chunk 1 POST--|  |--chunk 2 POST--|
                        |                       |
Audio play:    |====chunk 1 audio====|====chunk 2====|
```

Sentence boundary detection splits on `.`, `!`, `?`, or after ~100 characters at the nearest word boundary. This means the user starts hearing the response ~1-2 seconds after OpenClaw begins generating.

---

## Dependencies

| Package | Purpose | Size Impact |
|---------|---------|-------------|
| [WhisperKit](https://github.com/argmaxinc/WhisperKit) | On-device speech-to-text | ~5 MB code + 250MB-1.6GB model (downloaded) |
| [KeychainAccess](https://github.com/kishikawakatsumi/KeychainAccess) | Secure credential storage | Minimal |
| [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui) | Markdown rendering in chat | Minimal |

No WebRTC, no LiveKit, no Pipecat. The TTS and OpenClaw clients are simple HTTP via `URLSession`.

---

## Security

| Layer | Implementation |
|-------|---------------|
| Token/key storage | iOS Keychain (via KeychainAccess) |
| Transport | HTTPS-only enforced (rejects `http://` URLs) |
| TLS | Minimum TLS 1.2 enforced |
| Speech-to-text | Entirely on-device (audio never leaves phone) |
| Chat history | Stored locally with iOS Data Protection (encrypted at rest) |
| Network access | Cloudflare Tunnel or Tailscale (no open ports) |

---

## Configuration

| Setting | Storage | Example |
|---------|---------|---------|
| Gateway URL | UserDefaults | `https://openclaw.yourdomain.com` |
| Gateway Token | Keychain | `your-secure-token` |
| API Mode | UserDefaults | Chat Completions / Open Responses |
| TTS Provider | UserDefaults | ElevenLabs / OpenAI / Apple |
| ElevenLabs API Key | Keychain | `xi-...` |
| ElevenLabs Voice ID | UserDefaults | `21m00Tcm4TlvDq8ikWAM` |
| OpenAI API Key | Keychain | `sk-...` |
| OpenAI Voice | UserDefaults | `alloy` / `nova` / `shimmer` |
| Whisper Model | UserDefaults | `small.en` / `large-v3-turbo` |
| Voice Input | UserDefaults | Enabled / Disabled |
| Voice Output | UserDefaults | Enabled / Disabled |
| Show Token Usage | UserDefaults | On / Off (requires Open Responses) |
