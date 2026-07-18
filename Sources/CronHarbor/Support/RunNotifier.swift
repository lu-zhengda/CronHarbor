import Foundation
import UserNotifications

/// Posts local notifications for Run Now completions.
///
/// Notifications are strictly optional: everything degrades to silence when
/// the user declines authorization or the process is running outside a real
/// app bundle (for example under `swift test`), where the notification
/// framework is unavailable.
@MainActor
final class RunNotifier {
    static let shared = RunNotifier()

    /// UNUserNotificationCenter aborts when the process has no bundle
    /// identity, so every entry point checks this first.
    private let isSupported = Bundle.main.bundleIdentifier != nil
        && Bundle.main.bundleURL.pathExtension == "app"

    private init() {}

    func requestAuthorization() async -> Bool {
        guard isSupported else { return false }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .denied:
            return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    func notify(about record: RunRecord) {
        guard isSupported else { return }
        let content = UNMutableNotificationContent()
        content.title = record.jobName
        let duration = record.duration.formatted(.number.precision(.fractionLength(1)))
        content.body = record.succeeded
            ? "Run Now completed in \(duration)s."
            : "Run Now failed with exit \(record.exitCode) after \(duration)s."
        if !record.succeeded {
            content.sound = .default
        }
        let request = UNNotificationRequest(
            identifier: record.id.uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
