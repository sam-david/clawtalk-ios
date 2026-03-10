# ClawTalk iOS — Feature Roadmap & Research

## Current State

What's built and working:
- Streaming chat via `POST /v1/chat/completions` (SSE)
- Open Responses API via `POST /v1/responses` (structured SSE with token usage)
- Push-to-talk voice input (WhisperKit on-device STT)
- Conversation mode (VAD, auto-listen, interrupt, echo cancellation)
- Pluggable TTS (ElevenLabs, OpenAI, Apple)
- Multi-agent channels (per-agent routing via `openclaw:<agentId>`)
- Image sending (up to 8 per message, base64 JPEG, both APIs)
- Settings UI (gateway config, API mode, voice toggles, TTS/STT config, token usage display)
- Secure credential storage (iOS Keychain)
- HTTPS-only enforcement
- Conversation persistence (per-channel, local)
- WhisperKit model download with progress bar
- Markdown rendering in assistant messages
- Stop speaking button (both regular and conversation mode)

---

## Feature Backlog

### Phase 1 — Quick Wins

- [x] **Multi-agent channels**
  - OpenClaw supports `"openclaw:<agentId>"` in the model field to route to different agents
  - Also supports `x-openclaw-agent-id` header
  - Channel model (name, emoji, agentId) with channel list/picker UI
  - Each channel gets its own conversation history

- [x] **Image sending**
  - Both Chat Completions and Open Responses endpoints accept base64 images
  - Up to 8 images per message, 20 MB total
  - Photo picker + camera capture in chat input
  - Supported: JPEG, PNG, GIF, WebP, HEIC, HEIF

- [x] **Stop speaking button in conversation mode**
  - Available in both regular and conversation mode UI

### Phase 2 — Richer API Support

- [x] **OpenResponses API (`POST /v1/responses`)**
  - Richer item-based streaming with structured events
  - Event types: `response.output_text.delta`, `response.completed`, `response.failed`
  - Token usage reporting (input/output counts)
  - Configurable via Settings (API Mode picker)
  - Requires `gateway.http.endpoints.responses.enabled: true`

- [ ] **Fix `input_tokens` reporting in Open Responses API**
  - Gateway reports incorrect `input_tokens` in `response.completed` events
  - Short messages can show higher counts than long ones — values don't correlate with input length
  - `output_tokens` and `total_tokens` appear accurate
  - Fix likely in `src/gateway/openresponses-http.ts`
  - Once fixed, restore `input/output` token display in ClawTalk (currently output-only)

- [x] **Direct tool invocation (`POST /tools/invoke`)**
  - Tools dashboard accessible from channel list toolbar (wrench icon)
  - Implemented: memory_search, memory_get, agents_list, sessions_list, session_status, session_history, browser (status/screenshot/tabs), read (files)
  - Tool availability probing on view appear — unavailable tools shown greyed out
  - Agent picker in New Channel flow (with manual fallback for unlisted agents)
  - Reference: `src/gateway/tools-invoke-http.ts`

- [ ] **Server-side session management for HTTP API** ⚠️ REQUIRES GATEWAY PR
  - **Problem:** The gateway HTTP API (`/v1/chat/completions`, `/v1/responses`) does NOT persist sessions between requests. Only WebSocket/auto-reply flows (Telegram, Discord, etc.) call `updateSessionStore()` after each message.
  - **Impact on ClawTalk:**
    - Agent doesn't get SOUL.md personality injection (no system prompt)
    - Agent can't use tools mid-conversation (memory, browser, etc.)
    - No server-side context compaction (full history sent every request)
    - Sessions don't appear in the sessions list
    - No server-side token tracking
    - Memory is never written from ClawTalk conversations
  - **Current workaround:** Send full conversation history with each HTTP request. Session key header (`x-openclaw-session-key`) is sent for routing/identification but session is not persisted.
  - **What a gateway PR would need:**
    - Call `updateSessionStore()` after HTTP API agent command execution
    - Persist session entry with channel "clawtalk", session key, timestamps
    - This would give ClawTalk the same session management as Telegram/Discord
  - **Key files to modify:**
    - `src/gateway/openai-http.ts` — Chat completions handler
    - `src/gateway/openresponses-http.ts` — Responses handler
    - `src/commands/agent.ts` — Session persistence logic (lines 737-752)
    - `src/gateway/session-utils.ts` — Session store utilities
  - Session key format: `agent:<agentId>:clawtalk-user:<deviceId>:<channelUUID>`
  - Session version bumped on "Clear Chat" to create fresh server-side session

### Phase 3 — WebSocket & Real-Time

- [x] **WebSocket control plane**
  - Protocol v3: `ws://gateway:18789` or `wss://gateway/ws` (tunneled)
  - Bidirectional — can receive events (presence, approvals, status)
  - Handshake: challenge → connect (Ed25519 signature) → hello-ok
  - `chat.send`, `chat.history`, `chat.abort` implemented
  - Device identity persistence, auto-connect on channel select
  - **Default mode is HTTP** — WebSocket is opt-in via Settings
  - Device pairing required for remote WebSocket connections (`openclaw devices approve`)

- [x] **WebSocket image support**
  - `chat.send` accepts `attachments` array with base64 image data
  - Format: `{type: "image", mimeType: "image/jpeg", content: "<base64>"}`
  - Max 5MB per attachment
  - No longer falls back to HTTP for image messages

- [x] **Model selection** (WebSocket-only)
  - Fetch models from `models.list` RPC over WebSocket (no HTTP `/v1/models` endpoint)
  - Per-channel model picker (model picker sheet from chat input)
  - Per-message model selector (CPU icon in chat input bar)
  - Both change the same channel-level `selectedModel` setting
  - Default uses agent routing (`openclaw:<agentId>`)

- [x] **Display model in responses**
  - Parse `model` field from Chat Completions chunks and Open Responses `response.completed`
  - Show model name under assistant message bubble alongside token usage
  - **Note:** WebSocket chat events do NOT include model name — HTTP only

#### WebSocket vs HTTP — Known Gaps (Gateway-side)

These are limitations in the OpenClaw gateway, not ClawTalk. Documented here for upstream fixes.

| Feature | HTTP | WebSocket | Notes |
|---------|------|-----------|-------|
| Chat streaming | SSE | Push events | Both work |
| Images | Yes | Yes | WS uses `attachments` param |
| Model name in response | Yes | **No** | Not in chat events |
| Token usage | Yes (Open Responses) | **No** | Schema has `usage` field but never populated |
| Models list | **No** | Yes | No HTTP `/v1/models` endpoint |
| Chat abort | **No** | Yes | `chat.abort` RPC |
| Session persistence | **No** | **No** | WS `chat.send` creates transcripts but not session store entries |
| Device pairing | Not required | Required | Remote WS needs `openclaw devices approve` |

**Session persistence detail:** WebSocket `chat.send` calls `loadSessionEntry()` but never `resolveSessionStoreEntry()`. Telegram/Discord handlers DO call `resolveSessionStoreEntry()` which is why their sessions appear in `sessions_list`. A gateway PR to add `resolveSessionStoreEntry()` to `chat.send` would give ClawTalk persistent sessions.

**Key gateway source files for upstream fixes:**
- `src/gateway/server-methods/chat.ts` (lines 843-1247) — chat.send handler
- `src/gateway/server-chat.ts` (lines 341-477) — chat event emission (add model/usage here)
- `src/gateway/protocol/schema/logs-chat.ts` (lines 64-81) — chat event schema
- `src/config/sessions/store.ts` (lines 115-154) — session store persistence

- [ ] **Real-time events via WebSocket**
  - Agent status changes (push events)
  - Presence/heartbeat

- [ ] **Exec approvals from phone** (WebSocket unlocked)
  - Agent requests permission to run a command
  - Push notification / in-app approval dialog
  - User approves or denies from ClawTalk
  - Requires `operator.approvals` scope

- [ ] **Memory/tools via WebSocket RPC**
  - Route `memory.search`, `tools.catalog` through WebSocket instead of HTTP `/tools/invoke`
  - Lower latency, reuses existing connection
  - Fallback to HTTP when WebSocket unavailable

### Phase 4 — Node Mode (Device as Agent Peripheral)

- [ ] **Register as an OpenClaw node**
  - iOS app registers over WebSocket with role `"node"`
  - Declares capabilities: `camera`, `canvas`, `screen`, `location`, `voice`, `notifications`, `device`
  - Agent can then invoke device features remotely via `node.invoke`
  - Device pairing + approval workflow for security
  - Reference: `docs/platforms/ios.md`

- [ ] **Camera capability**
  - Agent can request photos/video from the phone's camera
  - `camera_snap` / `camera_record` commands
  - Return base64 or upload to agent workspace

- [ ] **Location capability**
  - Agent can request GPS coordinates
  - Useful for location-aware tasks

- [ ] **Canvas/A2UI**
  - Agent-driven visual workspace rendered in WKWebView
  - Agent can push HTML/JS to canvas, evaluate scripts, take snapshots
  - Operations: `canvas_navigate`, `canvas_eval`, `canvas_snapshot`, `canvas_present`
  - Could be a secondary tab/view in the app

- [ ] **Screen capability**
  - Agent can request screenshots of the app/device
  - `screen_snapshot` / `screen_record`

- [ ] **Notifications**
  - Agent can push local notifications to the device

### Phase 5 — Pre-Release Polish

- [x] **Onboarding flow**
  - 5-step wizard: welcome, gateway setup guide, gateway config, connection test, voice setup
  - Link to OpenClaw docs for gateway configuration
  - Connection test with error classification (auth/network/SSL)
  - Auto-skip for existing configured users

- [x] **Haptic feedback**
  - Talk button: medium on press, heavy on hold threshold, light on release
  - Send button: light impact on tap
  - Success/error notification haptics on message completion
  - Configurable via "Haptic Feedback" toggle in Settings

- [x] **Better error recovery**
  - Error classification: auth (401/403), network (timeout/unreachable), server (5xx), agent errors
  - Retry button on failed user messages
  - User-friendly error messages
  - Allow HTTP for local/private network addresses

- [ ] **Connection status indicator**
  - Show green/yellow/red dot for WebSocket connection state
  - Branch `feature/connection-status-dot` has partial work
  - Needs investigation: @Observable state updates from WS callbacks not reaching UI

- [ ] **Channel editing**
  - Rename existing channels
  - Change agent on existing channels
  - Reorder channels

- [ ] **Long-press context menu on messages**
  - Copy message text
  - Delete individual messages

---

## OpenClaw API Reference (Quick Reference)

### Endpoints

| Endpoint | Method | Purpose | Auth |
|---|---|---|---|
| `/v1/chat/completions` | POST | Streaming chat | Bearer token |
| `/v1/models` | GET | List available models | Bearer token |
| `/v1/responses` | POST | Rich item-based chat (files, tools) | Bearer token |
| `/tools/invoke` | POST | Direct tool invocation | Bearer token |
| WebSocket `:18789` | WS | Control plane, real-time events | Device identity + signature |

### Agent Routing

- Via model field: `"openclaw:main"` (default) or `"openclaw:<agentId>"`
- Via header: `x-openclaw-agent-id: <agentId>`

### Image Support (Chat Completions)

- Max 8 images per request
- Max 20 MB total
- MIME types: image/jpeg, image/png, image/gif, image/webp, image/heic, image/heif
- Format: base64 data URI in message content

### Tool Profiles

- `minimal` — basic tools only
- `coding` — filesystem + exec
- `messaging` — session + channel tools
- `full` — everything

### Tool Groups

- `group:runtime` — exec, process management
- `group:fs` — filesystem read/write
- `group:sessions` — session management
- `group:memory` — memory search/get
- `group:web` — browser control
- `group:ui` — canvas, notifications

### Key Source Files (OpenClaw)

- `src/gateway/openai-http.ts` — Chat completions handler
- `src/gateway/openresponses-http.ts` — Responses API handler
- `src/gateway/tools-invoke-http.ts` — Tool invocation handler
- `src/gateway/server/ws-connection.ts` — WebSocket handshake
- `src/channels/registry.ts` — Channel registry
- `docs/gateway/protocol.md` — WebSocket protocol spec
- `docs/gateway/openai-http-api.md` — Chat API docs
- `docs/gateway/openresponses-http-api.md` — Responses API docs
- `docs/gateway/tools-invoke-http-api.md` — Tool invoke docs
- `docs/platforms/ios.md` — iOS node guide
