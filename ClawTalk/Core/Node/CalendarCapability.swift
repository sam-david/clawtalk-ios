import Foundation
import EventKit

enum CalendarCapability {

    struct CalendarEvent: Encodable {
        let title: String
        let startDate: String
        let endDate: String
        let location: String?
        let notes: String?
        let isAllDay: Bool
        let calendarName: String
    }

    struct ReminderResult: Encodable {
        let title: String
        let isCompleted: Bool
        let dueDate: String?
        let notes: String?
        let priority: Int
        let listName: String
    }

    struct AddResult: Encodable {
        let ok: Bool
        let identifier: String
    }

    enum CalendarError: LocalizedError {
        case denied(String)
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .denied(let type): return "\(type) permission denied"
            case .failed(let msg): return msg
            }
        }
    }

    private static let store = EKEventStore()
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Calendar Events

    static func listEvents(daysAhead: Int = 7, daysBack: Int = 0) async throws -> [CalendarEvent] {
        try await requestCalendarAccess()

        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: now)!
        let end = Calendar.current.date(byAdding: .day, value: daysAhead, to: now)!

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)

        return events.map { event in
            CalendarEvent(
                title: event.title ?? "",
                startDate: formatter.string(from: event.startDate),
                endDate: formatter.string(from: event.endDate),
                location: event.location,
                notes: event.notes,
                isAllDay: event.isAllDay,
                calendarName: event.calendar?.title ?? ""
            )
        }
    }

    static func addEvent(
        title: String,
        startDate: String,
        endDate: String?,
        location: String?,
        notes: String?,
        isAllDay: Bool?
    ) async throws -> AddResult {
        try await requestCalendarAccess()

        guard let start = formatter.date(from: startDate) else {
            throw CalendarError.failed("Invalid start date format")
        }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.isAllDay = isAllDay ?? false

        if let endDate, let end = formatter.date(from: endDate) {
            event.endDate = end
        } else {
            event.endDate = Calendar.current.date(byAdding: .hour, value: 1, to: start)!
        }

        event.location = location
        event.notes = notes
        event.calendar = store.defaultCalendarForNewEvents

        try store.save(event, span: .thisEvent)
        return AddResult(ok: true, identifier: event.eventIdentifier)
    }

    // MARK: - Reminders

    static func listReminders(completed: Bool? = nil) async throws -> [ReminderResult] {
        try await requestRemindersAccess()

        let predicate = store.predicateForReminders(in: nil)
        let reminders = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[EKReminder], Error>) in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }

        var results = reminders.map { reminder in
            ReminderResult(
                title: reminder.title ?? "",
                isCompleted: reminder.isCompleted,
                dueDate: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }.map { formatter.string(from: $0) },
                notes: reminder.notes,
                priority: reminder.priority,
                listName: reminder.calendar?.title ?? ""
            )
        }

        if let completed {
            results = results.filter { $0.isCompleted == completed }
        }

        return results
    }

    static func addReminder(
        title: String,
        dueDate: String?,
        notes: String?,
        priority: Int?
    ) async throws -> AddResult {
        try await requestRemindersAccess()

        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        reminder.priority = priority ?? 0
        reminder.calendar = store.defaultCalendarForNewReminders()

        if let dueDate, let date = formatter.date(from: dueDate) {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: date
            )
        }

        try store.save(reminder, commit: true)
        return AddResult(ok: true, identifier: reminder.calendarItemIdentifier)
    }

    // MARK: - Authorization

    private static func requestCalendarAccess() async throws {
        if #available(iOS 17.0, *) {
            let granted = try await store.requestFullAccessToEvents()
            guard granted else { throw CalendarError.denied("Calendar") }
        } else {
            let granted = try await store.requestAccess(to: .event)
            guard granted else { throw CalendarError.denied("Calendar") }
        }
    }

    private static func requestRemindersAccess() async throws {
        if #available(iOS 17.0, *) {
            let granted = try await store.requestFullAccessToReminders()
            guard granted else { throw CalendarError.denied("Reminders") }
        } else {
            let granted = try await store.requestAccess(to: .reminder)
            guard granted else { throw CalendarError.denied("Reminders") }
        }
    }
}

// MARK: - Params

struct CalendarEventsParams: Decodable {
    let daysAhead: Int?
    let daysBack: Int?
}

struct CalendarAddParams: Decodable {
    let title: String
    let startDate: String
    let endDate: String?
    let location: String?
    let notes: String?
    let isAllDay: Bool?
}

struct RemindersListParams: Decodable {
    let completed: Bool?
}

struct RemindersAddParams: Decodable {
    let title: String
    let dueDate: String?
    let notes: String?
    let priority: Int?
}
