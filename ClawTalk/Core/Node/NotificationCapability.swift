import Foundation
import UserNotifications

enum NotificationCapability {

    enum NotificationError: LocalizedError {
        case denied
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .denied: return "Notification permission denied"
            case .failed(let msg): return msg
            }
        }
    }

    static func notify(
        title: String?,
        body: String?,
        sound: String?,
        priority: String?
    ) async throws {
        let center = UNUserNotificationCenter.current()

        // Request permission if not yet determined
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if !granted { throw NotificationError.denied }
        } else if settings.authorizationStatus == .denied {
            throw NotificationError.denied
        }

        let content = UNMutableNotificationContent()
        content.title = title ?? "OpenClaw"
        content.body = body ?? ""

        // Sound
        if let sound, sound == "critical" {
            content.sound = .defaultCritical
        } else {
            content.sound = .default
        }

        // Interruption level from priority
        if let priority {
            switch priority {
            case "critical":
                content.interruptionLevel = .critical
            case "urgent", "high":
                content.interruptionLevel = .timeSensitive
            case "low":
                content.interruptionLevel = .passive
            default:
                content.interruptionLevel = .active
            }
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // deliver immediately
        )

        try await center.add(request)
    }
}
