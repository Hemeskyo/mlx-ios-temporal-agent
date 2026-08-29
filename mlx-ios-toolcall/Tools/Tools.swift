//
//  Tools.swift
//  mlx-ios-toolcall
//

import Foundation
import MLXLMCommon

// MARK: - Tool definitions

/// Create a reminder with a text and a time.
struct ReminderInput: Codable {
    let text: String
    let time: String
}
struct ReminderOutput: Codable { let ok: Bool }

let reminderTool = Tool<ReminderInput, ReminderOutput>(
    name: "create_reminder",
    description: "Create a reminder with a text and a time in 24-hour format.",
    parameters: [
        .required("text", type: .string, description: "What to be reminded about."),
        .required("time", type: .string, description: "Time in 24-hour format, e.g. 18:00."),
    ]
) { input in ReminderOutput(ok: true) }


/// Schedule a calendar event.
struct CalendarInput: Codable {
    let title: String
    let start_time: String
    let duration_minutes: Int?
}
struct CalendarOutput: Codable { let ok: Bool }

let calendarTool = Tool<CalendarInput, CalendarOutput>(
    name: "schedule_calendar_event",
    description: "Schedule a calendar event with a title, a start time, and an optional duration.",
    parameters: [
        .required("title", type: .string, description: "Title of the event."),
        .required("start_time", type: .string, description: "Start time in 24-hour or ISO format."),
        .optional("duration_minutes", type: .int, description: "Duration of the event in minutes."),
    ]
) { input in CalendarOutput(ok: true) }


/// Send a text message to a contact.
struct MessageInput: Codable {
    let recipient: String
    let message: String
}
struct MessageOutput: Codable { let ok: Bool }

let messageTool = Tool<MessageInput, MessageOutput>(
    name: "send_message",
    description: "Send a text message to a contact.",
    parameters: [
        .required("recipient", type: .string, description: "Name of the contact."),
        .required("message", type: .string, description: "The body of the message."),
    ]
) { input in MessageOutput(ok: true) }


/// Start a countdown timer.
struct TimerInput: Codable {
    let duration_seconds: Int
    let label: String?
}
struct TimerOutput: Codable { let ok: Bool }

let timerTool = Tool<TimerInput, TimerOutput>(
    name: "start_timer",
    description: "Start a countdown timer for a number of seconds.",
    parameters: [
        .required("duration_seconds", type: .int, description: "Duration of the timer in seconds."),
        .optional("label", type: .string, description: "Optional label for the timer."),
    ]
) { input in TimerOutput(ok: true) }


/// Open Maps with directions to a destination.
struct MapsInput: Codable {
    let destination: String
}
struct MapsOutput: Codable { let ok: Bool }

let mapsTool = Tool<MapsInput, MapsOutput>(
    name: "open_maps",
    description: "Open Maps with directions to a destination.",
    parameters: [
        .required("destination", type: .string, description: "Where to navigate to."),
    ]
) { input in MapsOutput(ok: true) }


// MARK: - Registry & dispatch

/// Every tool schema exposed to the model. Add a tool here to make it available.
let allToolSchemas: [ToolSpec] = [
    reminderTool.schema,
    calendarTool.schema,
    messageTool.schema,
    timerTool.schema,
    mapsTool.schema,
]

/// Routes a parsed tool call to its handler and returns a readable result.
func dispatch(_ call: ToolCall) async -> String {
    let args = call.function.arguments
    switch call.function.name {

    case "create_reminder":
        let text = args["text"]?.displayString ?? ""
        let time = args["time"]?.displayString ?? ""
        do { return try await AppleEvents.createReminder(text: text, time: time) }
        catch { return "Reminder failed: \(error.localizedDescription)" }

    case "schedule_calendar_event":
        let title = args["title"]?.displayString ?? ""
        let start = args["start_time"]?.displayString ?? ""
        let duration = args["duration_minutes"].flatMap { Int($0.displayString) }
        do { return try await AppleEvents.createEvent(title: title, startTime: start, durationMinutes: duration) }
        catch { return "Event failed: \(error.localizedDescription)" }

    case "send_message":
        let recipient = args["recipient"]?.displayString ?? ""
        let message = args["message"]?.displayString ?? ""
        return await DeviceActions.sendMessage(recipient: recipient, message: message)

    case "start_timer":
        let seconds = args["duration_seconds"].flatMap { Int($0.displayString) } ?? 0
        let label = args["label"]?.displayString
        return await DeviceActions.startTimer(seconds: seconds, label: label)

    case "open_maps":
        let destination = args["destination"]?.displayString ?? ""
        return await DeviceActions.openMaps(destination: destination)

    default:
        return "Unknown tool: \(call.function.name)"
    }
}
