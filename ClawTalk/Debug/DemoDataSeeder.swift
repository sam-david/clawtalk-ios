#if DEBUG
import Foundation

/// Seeds fake conversation data for screenshots and app preview recordings.
///
/// Usage: Add launch arguments in Xcode scheme:
///   --seed-demo general        — general assistant conversation
///   --seed-demo coding         — code help conversation
///   --seed-demo creative       — creative writing conversation
///   --seed-demo tools          — conversation showcasing tool usage
///   --seed-demo all            — seeds all templates across multiple channels
///
/// The seeder writes directly to the default channel's conversation file.
/// Clear with --seed-demo clear.
enum DemoDataSeeder {

    /// Call BEFORE ChannelStore/SettingsStore are created so @State picks up seeded data.
    static func seedIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "--seed-demo"),
              idx + 1 < args.count else { return }
        let template = args[idx + 1].lowercased()

        // Skip onboarding so we land on the channel list
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")

        if template == "clear" {
            ConversationStore.shared.clearAll()
            UserDefaults.standard.removeObject(forKey: "channels")
            print("[DemoDataSeeder] Cleared all data")
            return
        }

        if template == "all" {
            seedAllTemplates()
            return
        }

        guard let messages = conversations[template] else {
            print("[DemoDataSeeder] Unknown template: \(template)")
            print("[DemoDataSeeder] Available: \(conversations.keys.sorted().joined(separator: ", "))")
            return
        }

        // Read existing channels or create default
        let channels = loadChannels()
        let channel = channels.first ?? .default
        if channels.isEmpty {
            saveChannels([channel])
        }

        let seeded = buildMessages(from: messages)
        ConversationStore.shared.save(seeded, channelId: channel.id)
        print("[DemoDataSeeder] Seeded \(seeded.count) messages (\(template)) into channel '\(channel.name)'")
    }

    // MARK: - Seed All

    private static func seedAllTemplates() {
        // Sorted so assignment to channels is deterministic
        let templateOrder = ["general", "coding", "creative", "tools"]
        var channels: [Channel] = []

        for name in templateOrder {
            guard let messages = conversations[name] else { continue }
            let emoji = channelEmojis[name] ?? "💬"
            let channelName = channelNames[name] ?? name.capitalized
            let channel = Channel(name: channelName, agentId: "main", systemEmoji: emoji)
            channels.append(channel)

            let seeded = buildMessages(from: messages)
            ConversationStore.shared.save(seeded, channelId: channel.id)
            print("[DemoDataSeeder] Created channel '\(channelName)' and seeded '\(name)' (\(seeded.count) messages)")
        }

        saveChannels(channels)
    }

    // MARK: - Direct UserDefaults Channel I/O

    private static func loadChannels() -> [Channel] {
        guard let data = UserDefaults.standard.data(forKey: "channels"),
              let decoded = try? JSONDecoder().decode([Channel].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func saveChannels(_ channels: [Channel]) {
        if let data = try? JSONEncoder().encode(channels) {
            UserDefaults.standard.set(data, forKey: "channels")
        }
    }

    private static let channelNames: [String: String] = [
        "general": "Main",
        "coding": "Code Help",
        "creative": "Writing",
        "tools": "Research",
    ]

    private static let channelEmojis: [String: String] = [
        "general": "🦞",
        "coding": "💻",
        "creative": "✍️",
        "tools": "🔧",
    ]

    // MARK: - Message Builder

    private static func buildMessages(from pairs: [(MessageRole, String, String?)]) -> [Message] {
        let calendar = Calendar.current
        let now = Date()
        // Space messages ~2 minutes apart, starting 30 min ago
        let startOffset = -(pairs.count * 2 * 60)

        return pairs.enumerated().map { index, pair in
            let (role, content, model) = pair
            let offset = startOffset + (index * 2 * 60)
            let timestamp = calendar.date(byAdding: .second, value: offset, to: now)!
            let msg = Message(role: role, content: content)
            return patchTimestamp(msg, to: timestamp, modelName: model)
        }
    }

    private static func patchTimestamp(_ message: Message, to date: Date, modelName: String?) -> Message {
        // Since Message.timestamp is let, we rebuild via Codable round-trip
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var dict = try? JSONSerialization.jsonObject(
            with: encoder.encode(message)
        ) as? [String: Any] else { return message }

        let formatter = ISO8601DateFormatter()
        dict["timestamp"] = formatter.string(from: date)
        if let model = modelName {
            dict["modelName"] = model
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let patched = try? decoder.decode(Message.self, from: data) else { return message }
        return patched
    }

    // MARK: - Conversation Templates

    /// Each template is an array of (role, content, modelName?) tuples.
    static let conversations: [String: [(MessageRole, String, String?)]] = [

        // --- General assistant conversation ---
        "general": [
            (.user, "Hey! What can you help me with?", nil),
            (.assistant, """
            Hi! I'm your AI assistant running on your OpenClaw gateway. Here's what I can do:

            - **Answer questions** on any topic
            - **Write and debug code** in any language
            - **Analyze images** you send me
            - **Search my memory** for things we've discussed before
            - **Browse the web** to find current information
            - **Read and write files** in my workspace

            Just ask me anything, or tap the mic to talk!
            """, "Claude Sonnet 4"),

            (.user, "What's the weather like in San Francisco today?", nil),
            (.assistant, """
            Let me check that for you.

            Based on current conditions in San Francisco:

            **Today — March 14, 2026**
            - Partly cloudy, 62°F (17°C)
            - Wind: 12 mph from the west
            - Humidity: 68%
            - High: 65°F / Low: 52°F

            Pretty typical for mid-March in SF — layers are your friend! The fog should roll in later this evening.
            """, "Claude Sonnet 4"),

            (.user, "Can you remember that I prefer Celsius from now on?", nil),
            (.assistant, "Done — saved to memory. I'll use Celsius for you from now on.", "Claude Sonnet 4"),
        ],

        // --- Coding conversation ---
        "coding": [
            (.user, "How do I make a SwiftUI view that pulses with an animation?", nil),
            (.assistant, """
            Here's a clean pulsing animation:

            ```swift
            struct PulsingView: View {
                @State private var isPulsing = false

                var body: some View {
                    Circle()
                        .fill(.blue)
                        .frame(width: 60, height: 60)
                        .scaleEffect(isPulsing ? 1.2 : 1.0)
                        .opacity(isPulsing ? 0.7 : 1.0)
                        .animation(
                            .easeInOut(duration: 0.8)
                            .repeatForever(autoreverses: true),
                            value: isPulsing
                        )
                        .onAppear { isPulsing = true }
                }
            }
            ```

            The key is `.repeatForever(autoreverses: true)` which creates the continuous pulse. You can layer multiple circles with different timing for a ripple effect.
            """, "Claude Sonnet 4"),

            (.user, "Nice! Can you add a ripple ring effect around it?", nil),
            (.assistant, """
            Here's the enhanced version with expanding ripple rings:

            ```swift
            struct PulsingRippleView: View {
                @State private var isPulsing = false

                var body: some View {
                    ZStack {
                        // Outer ripple rings
                        ForEach(0..<3, id: \\.self) { i in
                            Circle()
                                .stroke(.blue.opacity(0.3), lineWidth: 2)
                                .frame(width: 60, height: 60)
                                .scaleEffect(isPulsing ? 2.5 : 1.0)
                                .opacity(isPulsing ? 0 : 0.8)
                                .animation(
                                    .easeOut(duration: 2.0)
                                    .repeatForever(autoreverses: false)
                                    .delay(Double(i) * 0.6),
                                    value: isPulsing
                                )
                        }

                        // Center circle
                        Circle()
                            .fill(.blue)
                            .frame(width: 60, height: 60)
                            .scaleEffect(isPulsing ? 1.1 : 1.0)
                            .animation(
                                .easeInOut(duration: 0.8)
                                .repeatForever(autoreverses: true),
                                value: isPulsing
                            )
                    }
                    .onAppear { isPulsing = true }
                }
            }
            ```

            The three rings expand outward with staggered delays, creating a sonar/radar pulse effect. Each ring fades to transparent as it expands.
            """, "Claude Sonnet 4"),

            (.user, "What about making a custom button style that has a press-down effect?", nil),
            (.assistant, """
            ```swift
            struct PressDownButtonStyle: ButtonStyle {
                func makeBody(configuration: Configuration) -> some View {
                    configuration.label
                        .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
                        .opacity(configuration.isPressed ? 0.8 : 1.0)
                        .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
                }
            }

            // Usage
            Button("Tap Me") { }
                .buttonStyle(PressDownButtonStyle())
            ```

            `ButtonStyle` gives you `configuration.isPressed` which SwiftUI manages automatically. The 0.95 scale + slight opacity drop feels tactile without being overdone. You can combine it with a haptic in the action for extra polish.
            """, "Claude Sonnet 4"),
        ],

        // --- Creative writing conversation ---
        "creative": [
            (.user, "I need help writing a short bio for my portfolio site. I'm a mobile developer who loves building tools for creative people.", nil),
            (.assistant, """
            Here are a few options — pick the tone that fits:

            **Casual & warm:**
            > I build apps that help creative people do their best work. By day I'm a mobile developer; by night I'm probably still a mobile developer, but with better snacks. I believe the best tools disappear into the workflow — you should be thinking about your art, not fighting your software.

            **Professional but human:**
            > Mobile developer focused on building intuitive tools for creators. I care about the details that make an app feel right — smooth animations, thoughtful interactions, and interfaces that stay out of your way. Currently working on projects at the intersection of AI and creative workflows.

            **Short & punchy:**
            > I make apps for people who make things. Mobile dev, tool builder, creative technologist.

            Want me to adjust any of these, or blend elements from different versions?
            """, "Claude Sonnet 4"),

            (.user, "I like the casual one but can you make it a bit shorter and mention that I work with AI?", nil),
            (.assistant, """
            > I build apps that help creative people do their best work — lately at the intersection of mobile and AI. I believe the best tools disappear into the workflow: you should be thinking about your art, not fighting your software.

            Two sentences, hits mobile + AI + creative focus. Want to tweak anything?
            """, "Claude Sonnet 4"),

            (.user, "Perfect. Now can you help me write a tagline for the site? Something memorable.", nil),
            (.assistant, """
            A few directions:

            **Tool-focused:**
            - *Tools for the people who make things.*
            - *Building what creators reach for.*

            **AI angle:**
            - *Where mobile meets imagination.*
            - *AI-powered tools, human-centered design.*

            **Minimal:**
            - *Make things that make things easier.*
            - *Software that gets out of the way.*

            My favorite is **"Building what creators reach for"** — it's concrete, implies quality and utility, and works as both a mission statement and a tagline.
            """, "Claude Sonnet 4"),
        ],

        // --- Tools/research conversation ---
        "tools": [
            (.user, "Can you check what sessions are active on the gateway right now?", nil),
            (.assistant, """
            I checked the active sessions. Here's what's running:

            | Session | Status | Last Active |
            |---------|--------|-------------|
            | `telegram-main` | Active | 2 min ago |
            | `discord-general` | Active | 8 min ago |
            | `web-ui` | Idle | 1 hour ago |

            Three sessions total — Telegram and Discord are actively being used, and there's an idle web UI session from earlier. Want me to dig into any of them?
            """, "Claude Sonnet 4"),

            (.user, "What about my memory? Search for anything about my project deadlines.", nil),
            (.assistant, """
            I searched my memory for project deadlines. Here's what I found:

            **1. Portfolio redesign**
            - Deadline: March 20, 2026
            - Status: Design phase complete, building out pages
            - Note: You wanted to launch before the conference

            **2. ClawTalk v1.0**
            - Deadline: End of March 2026
            - Status: App Store submission in progress
            - Note: Demo server set up, testing ongoing

            **3. API client library**
            - Deadline: April 15, 2026
            - Status: Planning phase
            - Note: Depends on gateway v2 API stabilizing

            The portfolio site is the most urgent — 6 days out. Want me to help prioritize tasks for that?
            """, "Claude Sonnet 4"),

            (.user, "Yeah, what should I focus on this weekend to hit that portfolio deadline?", nil),
            (.assistant, """
            Based on what I know about the project, here's a focused weekend plan:

            **Saturday — Content & Structure**
            - [ ] Finalize the bio (we just wrote that!)
            - [ ] Write project case studies (3 max — pick your strongest)
            - [ ] Gather screenshots and demo videos for each project
            - [ ] Set up the contact form

            **Sunday — Polish & Deploy**
            - [ ] Responsive testing on mobile + tablet
            - [ ] Performance pass (image optimization, lazy loading)
            - [ ] Deploy to production
            - [ ] Test all links and forms

            **Skip for now** (nice-to-have, not launch-blocking):
            - Blog section — add post-launch
            - Dark mode toggle — your current theme works fine
            - Analytics — add after launch

            The bio and tagline are done, so you're ahead of schedule on content. The case studies are the biggest time sink — keep them short and visual.
            """, "Claude Sonnet 4"),
        ],
    ]
}
#endif
