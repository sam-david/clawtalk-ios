# ClawTalk — Demo Recording Guide

Scripted prompts and instructions for capturing the App Store preview and
screenshots. The release headlines hands-free **Conversation Mode**, so
both the preview video and the screenshot ordering put it first.

---

## Setup

1. In Xcode: **Edit Scheme > Run > Arguments** — add the launch argument for the template you want
2. Build and run on the **iPhone 15 Pro Max** simulator (6.7" — required for App Store)
3. For screenshots: capture via `Cmd+S` in Simulator
4. For video: **Simulator > File > Record Screen**

---

## App Preview Video — Conversation Mode (the single preview)

We're publishing **one** App Preview rather than three. Reason: App Store
crams multiple previews up front, splitting viewer attention. A single
focused conversation-mode loop is the strongest possible signal of what
this app actually is.

### Recording script

**Setup:** `--seed-demo general` (so the channel has visible prior history)

**Steps:**

1. Launch app — channel list appears
2. Tap **Main** to enter the channel
3. Scroll the conversation up briefly to show prior turns (proves this isn't a blank screen)
4. Tap the **conversation mode** button (bubble icon)
5. Pulsing rings appear, "Listening…" label visible
6. Say clearly: **"What's a good book to read this month?"**
7. Wait for: VAD detects end-of-speech → "Transcribing…" → user message appears → assistant response streams in → TTS speaks the reply
8. **Second exchange (this is critical — proves it's hands-free):**
   - The mic should automatically resume listening after TTS finishes
   - Say: **"Something shorter, maybe under 200 pages?"**
   - Let the loop run again
9. Tap **End** to exit conversation mode
10. Stop recording

**Length target:** 20–28 seconds. Trim any dead air at the start.

**Audio:** include it. The TTS reply is half the point — viewers should hear the agent talk back. App Store autoplays muted, but a tap unmutes.

### Why this script

- The second exchange is what differentiates ClawTalk from every other "voice input" app. Most apps put you in dictation mode for *one* utterance. ClawTalk runs the loop continuously.
- Short prompts produce short replies → snappy preview without dead time.
- "Book recommendation" is universally relatable and shows a natural reply.

---

## Screenshot Shot List

Capture on **iPhone 15 Pro Max** simulator (1290 x 2796 px, required). Each
shot has a launch arg and exact framing notes.

| # | What | Launch arg | How to capture |
|---|------|-----------|----------------|
| 1 | **Conversation Mode active** | `--seed-demo general` | Open Main channel → tap conversation button → capture while pulsing rings are visible and "Listening…" label is showing. Try to catch the rings mid-pulse (not at the smallest/largest extreme). |
| 2 | Streaming markdown reply | `--seed-demo coding` | Open the coding channel → scroll to a fully-rendered response with a code block visible. Make sure the **"+"** attachment icon is in the input bar (not the legacy photo icon). |
| 3 | Onboarding welcome | _(fresh install — delete app first)_ | First launch, on the Welcome step. Shows the text-first onboarding hero. |
| 4 | Channel list | `--seed-demo all` | Stay on channel list, all 4 channels visible. |
| 5 | Tools dashboard | `--seed-demo general` | Open Tools (grid icon in nav bar). |
| 6 | Settings — Voice & TTS | `--seed-demo general` | Open Settings → scroll to the **Voice & TTS** section. Voice Input toggle + TTS Provider picker visible. |

### Specs

- iPhone 15 Pro Max (6.7"): 1290 x 2796 px — **required**
- iPhone 15 Pro (6.1"): 1179 x 2556 px — recommended (Apple will scale 6.7" down, but native is better)
- Format: PNG or JPEG, no alpha channel, 72 dpi minimum

---

## Available Seed Templates

For reference, the launch args supported by `--seed-demo`:

| Arg | Seeded context |
|-----|----------------|
| `--seed-demo general` | Casual Q&A — weather, memory preference |
| `--seed-demo coding` | SwiftUI animation questions — code blocks |
| `--seed-demo creative` | Portfolio bio and tagline writing |
| `--seed-demo tools` | Gateway sessions, deadlines, weekend planning |
| `--seed-demo all` | All four channels seeded (Main, Code Help, Writing, Research) |

---

## Tips

- **Dark mode is default** — the app looks best in dark mode, which is what ships
- **Pause on the response** — let the camera linger on a fully rendered response for 2-3 seconds before moving on
- **Trim dead time** — cut any loading/waiting at the start before the UI appears
- **For Conversation Mode**: do the recording with a quiet background. The mic picks up room noise less aggressively now (voice processing handles it), but a clean take still reads better.
- **Scrolling speed** — if the recording includes scrolling, do it slowly so text is readable in the final preview
