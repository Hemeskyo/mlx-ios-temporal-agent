//
//  DeviceActions.swift
//  mlx-ios-toolcall
//

import Foundation
import UIKit
import UserNotifications

/// Maps / Messages / Timer actions using the device's own apps and frameworks.
enum DeviceActions {

    /// Opens Apple Maps with driving directions to `destination`.
    @MainActor
    static func openMaps(destination: String) -> String {
        let query = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? destination
        guard let url = URL(string: "http://maps.apple.com/?daddr=\(query)") else {
            return "Couldn't open Maps."
        }
        UIApplication.shared.open(url)
        return "Opening Maps to \(destination)."
    }

    /// Schedules a local notification after `seconds` — an on-device timer alarm.
    static func startTimer(seconds: Int, label: String?) async -> String {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return "Notifications denied — can't set timer." }

        let content = UNMutableNotificationContent()
        content.title = label ?? "Timer"
        content.body = "Time's up!"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(1, seconds)), repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        do {
            try await center.add(request)
            return "Timer set for \(seconds)s\(label.map { " (\($0))" } ?? "")."
        } catch {
            return "Timer failed: \(error.localizedDescription)"
        }
    }

    /// Opens Messages prefilled with `message` (the recipient is chosen in Messages).
    @MainActor
    static func sendMessage(recipient: String, message: String) -> String {
        let body = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? message
        guard let url = URL(string: "sms:&body=\(body)") else {
            return "Couldn't open Messages."
        }
        UIApplication.shared.open(url)
        return "Opening Messages for \(recipient)."
    }
}
