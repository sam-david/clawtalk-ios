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
- HTTPS-only enforcement (HTTP allowed for local/private networks)
- Conversation persistence (per-channel, local)
- WhisperKit model download with progress bar
- Markdown rendering in assistant messages
- Stop speaking button (both regular and conversation mode)
- WebSocket control plane (chat, history, abort, models list)
- Tools dashboard (memory, agents, sessions, browser, models)
- JSON prettifier with syntax coloring in Tools views
- Model name display on assistant messages (HTTP only)
- Onboarding wizard with connection test
- Haptic feedback (configurable)

---

## Feature Backlog

### Phase 1 — Quick Wins (DONE)

- [x] **Multi-agent channels**
- [x] **Image sending**
- [x] **Stop speaking button in conversation mode**

### Phase 2 — Richer API Support

- [x] **OpenResponses API (`POST /v1/responses`)**
- [x] **Direct tool invocation (`POST /tools/invoke`)**
- [x] **Models list** (read-only, WebSocket-only, in Tools dashboard)

- [ ] **Fix `input_tokens` reporting in Open Responses API**
  - Gateway reports incorrect `input_tokens` in `response.completed` events
  - `output_tokens` and `total_tokens` appear accurate
  - Fix likely in `src/gateway/openresponses-http.ts`
  - Once fixed, restore `input/output` token display in ClawTalk (currently output-only)

- [ ] **File read in Tools dashboard** ⚠️ REQUIRES GATEWAY PR
  - `/tools/invoke` only exposes core OpenClaw tools — coding tools (`read`, `write`, `edit`, `exec`) are only available during full agent execution
  - **Fix:** Add `createOpenClawCodingTools()` call to `/tools/invoke`
  - Key files: `src/gateway/tools-invoke-http.ts` (~line 249), `src/agents/pi-tools.ts`

- [ ] **Server-side session management** ⚠️ REQUIRES GATEWAY PR
  - Gateway HTTP/WS APIs do NOT persist sessions between requests
  - Impact: no SOUL.md injection, no mid-conversation tool use, no memory writes, sessions don't appear in sessions list
  - **Fix:** Call `updateSessionStore()` after HTTP/WS agent command execution
  - Key files: `src/gateway/openai-http.ts`, `src/gateway/openresponses-http.ts`, `src/gateway/server-methods/chat.ts`, `src/commands/agent.ts` (lines 737-752)

- [ ] **HTTP models list** ⚠️ REQUIRES GATEWAY PR
  - No HTTP `/v1/models` endpoint — only WebSocket `models.list` RPC
  - **Fix:** Add `GET /v1/models` handler to gateway

### Phase 3 — WebSocket & Real-Time

- [x] **WebSocket control plane** (v3 protocol, chat.send/history/abort, device identity)
- [x] **WebSocket image support** (`attachments` array, max 5MB)
- [x] **Display model in responses** (HTTP only — WS chat events don't include model name)

- [x] **Real-time events via WebSocket**
  - Agent status changes (push events)
  - Approval request/resolved events

- [x] **Exec approvals from phone**
  - Agent requests permission to run a command
  - In-app approval banner with Allow Once / Allow Always / Deny
  - Haptic feedback on approval request
  - Countdown timer showing expiration
  - Requires `operator.approvals` scope (already included in handshake)

- [ ] **Memory/tools via WebSocket RPC**
  - Route `memory.search`, `tools.catalog` through WebSocket instead of HTTP `/tools/invoke`
  - Lower latency, reuses existing connection
  - Fallback to HTTP when WebSocket unavailable

#### WebSocket vs HTTP — Known Gaps (Gateway-side)

| Feature | HTTP | WebSocket | Notes |
|---------|------|-----------|-------|
| Chat streaming | SSE | Push events | Both work |
| Images | Yes | Yes | WS uses `attachments` param |
| Model name in response | Yes | **No** | Not in chat events |
| Token usage | Yes (Open Responses) | **No** | Schema has `usage` field but never populated |
| Models list | **No** | Yes | No HTTP `/v1/models` endpoint |
| Chat abort | **No** | Yes | `chat.abort` RPC |
| Session persistence | **No** | **No** | Neither path calls `resolveSessionStoreEntry()` |
| Device pairing | Not required | Required | Remote WS needs `openclaw devices approve` |

**Key gateway source files for upstream fixes:**
- `src/gateway/server-methods/chat.ts` (lines 843-1247) — chat.send handler
- `src/gateway/server-chat.ts` (lines 341-477) — chat event emission (add model/usage here)
- `src/gateway/protocol/schema/logs-chat.ts` (lines 64-81) — chat event schema
- `src/config/sessions/store.ts` (lines 115-154) — session store persistence

### Phase 4 — Node Mode (Device as Agent Peripheral)

The official OpenClaw iOS app (`apps/ios/`) operates as a `role: "node"` — a device peripheral the agent can invoke remotely. ClawTalk currently operates as a chat client only. Adding node mode would let the agent use the phone's hardware and sensors.

- [x] **Register as an OpenClaw node**
  - Register over WebSocket with `role: "node"`
  - Declare capabilities: `device`, `notifications`
  - Agent invokes device features remotely via `node.invoke`
  - Device pairing + approval workflow for security
  - Reference: `docs/platforms/ios.md`, official app `Sources/Capabilities/NodeCapabilityRouter.swift`

- [x] **Camera capability**
  - `camera.list` (enumerate cameras), `camera.snap` (take photo)
  - Front/back selection, quality, max width params
  - Return base64 JPEG image data
  - Reference: official app `Sources/Camera/CameraController.swift`

- [x] **Location capability**
  - Agent can request GPS coordinates via `location.get`
  - Returns lat/lng/altitude/accuracy/speed/course
  - Supports `whenInUse` authorization
  - Reference: official app `Sources/Location/LocationService.swift`

- [ ] **Canvas/A2UI**
  - Agent-driven visual workspace rendered in WKWebView
  - `canvas.present` / `canvas.navigate` — load URLs
  - `canvas.evalJS` — execute JavaScript in the webview
  - `canvas.snapshot` — capture webview as image
  - `a2ui.push` / `a2ui.pushJSONL` / `a2ui.reset` — push structured UI elements
  - Deep links (`openclaw://`) from within canvas trigger app actions
  - Could be a tab or secondary view in the app
  - Reference: official app `Sources/Screen/ScreenController.swift`, `ScreenTab.swift`

- [ ] **Screen capability**
  - Agent can request screenshots of the app/device via `screen.snapshot`
  - Screen recording via ReplayKit (`screen.record`)
  - Reference: official app `Sources/Screen/ScreenRecordService.swift`

- [x] **Local notifications**
  - Agent can push local notifications to the device via `system.notify`
  - Full `UNUserNotifications` integration with authorization flow
  - Reference: official app `Sources/Services/NotificationService.swift`

- [x] **Device info/status**
  - `device.status` — battery level, thermal state, locale, timezone
  - `device.info` — model, OS version, screen size
  - Reference: official app `Sources/Device/DeviceInfoHelper.swift`

- [x] **Contacts access**
  - `contacts.search` — search address book
  - `contacts.add` — create new contact
  - Reference: official app `Sources/Contacts/ContactsService.swift`

- [x] **Calendar/Reminders access**
  - `calendar.events` / `calendar.add` — query/create calendar events
  - `reminders.list` / `reminders.add` — query/create reminders
  - Reference: official app `Sources/Calendar/CalendarService.swift`, `Sources/Reminders/RemindersService.swift`

- [x] **Motion/Pedometer**
  - `motion.activity` — activity history (walking, running, cycling, automotive, stationary)
  - `motion.pedometer` — step counts, distance, floors
  - Reference: official app `Sources/Motion/MotionService.swift`

- [x] **Photos library access**
  - `photos.latest` — retrieve recent photos from device photo library
  - Configurable count, image inclusion, max width
  - Reference: official app `Sources/Media/PhotoLibraryService.swift`

- [ ] **Voice wake (keyword detection)**
  - On-device speech recognition listens for configurable wake words
  - Triggers agent interaction when keyword detected
  - Uses `SFSpeechRecognizer` for on-device recognition
  - `voicewake.set` / `voicewake.get` for configuration
  - Reference: official app `Sources/Voice/VoiceWakeManager.swift`

### Phase 5 — Pre-Release Polish

- [x] **Onboarding flow**
- [x] **Haptic feedback**
- [x] **Better error recovery**

- [ ] **Connection status indicator**
  - Show green/yellow/red dot for WebSocket connection state
  - Branch `feature/connection-status-dot` has partial work
  - Needs investigation: @Observable state updates from WS callbacks not reaching UI

- [x] **Channel editing**
  - Rename existing channels
  - Change agent on existing channels
  - Reorder channels (drag to reorder via `.onMove`)
  - Long-press context menu on channel rows (edit / delete)

- [x] **Long-press context menu on messages**
  - Copy message text to clipboard
  - Delete individual messages

- [ ] **QR code / setup code pairing**
  - Scan QR code or enter setup code to configure gateway connection
  - Faster onboarding than typing URLs manually
  - Reference: official app `Sources/Onboarding/QRScannerView.swift`, `Sources/Gateway/GatewaySetupCode.swift`

- [ ] **Gateway discovery (Bonjour/mDNS)**
  - Auto-discover OpenClaw gateways on the local network
  - Uses `_openclaw-gw._tcp` Bonjour browsing
  - TLS fingerprint trust prompts
  - Reference: official app `Sources/Gateway/GatewayDiscoveryModel.swift`

- [ ] **Deep link handling**
  - Handle `openclaw://` URL scheme for agent-initiated deep links
  - Confirmation dialogs and security limits
  - Reference: official app deep link handling

- [ ] **Share extension**
  - System share sheet integration
  - Share text, URLs, images, or video from other apps directly into the agent session
  - Requires separate app extension target
  - Reference: official app `ShareExtension/ShareViewController.swift`

- [ ] **Gateway status pill**
  - Persistent status overlay showing connection state and current activity
  - Tap to manage (reconnect, view details)
  - Reference: official app `Sources/Status/StatusPill.swift`

### Phase 6 — Platform Extensions

- [ ] **APNs push notifications**
  - Register APNs device token with gateway (`push.apns.register`)
  - Gateway can wake app and deliver push notifications
  - Requires push capability in provisioning profile

- [ ] **Live Activity (Dynamic Island / Lock Screen)**
  - Show gateway connection status as a Live Activity widget
  - Requires ActivityWidget extension target
  - Reference: official app `Sources/LiveActivity/LiveActivityManager.swift`

- [ ] **Apple Watch companion app**
  - `watch.status` — check if watch is paired/reachable
  - `watch.notify` — push notifications to the watch
  - Watch inbox view for messages
  - Significant effort — separate WatchKit extension
  - Reference: official app `WatchExtension/Sources/`

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

### Key Source Files (Official iOS App)

- `apps/ios/Sources/Capabilities/NodeCapabilityRouter.swift` — Node capability dispatch
- `apps/ios/Sources/Camera/CameraController.swift` — Camera snap/clip
- `apps/ios/Sources/Screen/ScreenController.swift` — Canvas/A2UI webview
- `apps/ios/Sources/Location/LocationService.swift` — GPS/geofencing
- `apps/ios/Sources/Voice/VoiceWakeManager.swift` — Wake word detection
- `apps/ios/Sources/Device/DeviceInfoHelper.swift` — Device info/status
- `apps/ios/Sources/Contacts/ContactsService.swift` — Contacts access
- `apps/ios/Sources/Calendar/CalendarService.swift` — Calendar events
- `apps/ios/Sources/Services/NotificationService.swift` — Local notifications
- `apps/ios/Sources/Gateway/GatewayDiscoveryModel.swift` — Bonjour discovery
- `apps/ios/Sources/Onboarding/QRScannerView.swift` — QR code pairing
- `apps/ios/ShareExtension/ShareViewController.swift` — Share extension
- `apps/ios/Sources/LiveActivity/LiveActivityManager.swift` — Dynamic Island
