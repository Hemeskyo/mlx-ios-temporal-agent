//
//  AppleEvents.swift
//  mlx-ios-toolcall
//

import Foundation
import EventKit

/// Wraps EventKit: requests permission and creates real reminders / calendar events.
enum AppleEvents {

    /// One shared event store for the whole app.
    static let store = EKEventStore()

    /// Creates a reminder titled `text`, due at `time` ("HH:mm") today.
    static func createReminder(text: String, time: String) async throws -> String {
        guard try await store.requestFullAccessToReminders() else {
            return "Reminders access denied."
        }
        guard let calendar = store.defaultCalendarForNewReminders() else {
            return "No reminders list available."
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = text
        reminder.calendar = calendar

        if let date = date(from: time) {
            reminder.dueDateComponents = Calendar.current
                .dateComponents([.year, .month, .day, .hour, .minute], from: date)
            reminder.addAlarm(EKAlarm(absoluteDate: date))
        }

        try store.save(reminder, commit: true)
        return "Reminder set: \(text) at \(time)"
    }

    /// Creates a calendar event titled `title`, starting at `startTime` ("HH:mm").
    static func createEvent(title: String, startTime: String, durationMinutes: Int?) async throws -> String {
        guard try await store.requestFullAccessToEvents() else {
            return "Calendar access denied."
        }
        guard let start = date(from: startTime) else {
            return "Couldn't understand the time \(startTime)."
        }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(TimeInterval((durationMinutes ?? 60) * 60))
        event.calendar = store.defaultCalendarForNewEvents

        try store.save(event, span: .thisEvent)
        return "Event scheduled: \(title) at \(startTime)"
    }

    /// Parses "HH:mm" into today's date at that time.
    private static func date(from time: String) -> Date?
    {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: Date())
    }
}
