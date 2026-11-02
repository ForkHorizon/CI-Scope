// Polls the server for security events, raises a notification for each new one, and acknowledges them on request.
import Combine
import Foundation
import UserNotifications

@MainActor
final class SecurityEventMonitor: ObservableObject {
    @Published private(set) var events: [SecurityEvent] = []
    @Published var message: String?

    var client = SecurityEventsClient()
    var readToken: () async throws -> String = { try await PolicyAuthorizer.configReadToken() }
    var adminLogin: (String) async throws -> (user: String, password: String) = { reason in
        let password = try await PolicyAuthorizer.adminPassword(reason: reason)
        return (try await PolicyGitHub(config: DashboardConfig()).login(), password)
    }
    var notify: (SecurityEvent) -> Void = SecurityEventMonitor.postNotification

    private var seen: Set<Int> = []

    /// Fetches open events; only events not seen before raise a notification.
    func refresh() async {
        do {
            let open = try await client.fetchOpen(readToken: try await readToken())
            for event in open where !seen.contains(event.id) {
                seen.insert(event.id)
                notify(event)
            }
            events = open
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    /// One Touch ID prompt acknowledges everything currently shown.
    func acknowledgeAll() async {
        guard !events.isEmpty else { return }
        do {
            let admin = try await adminLogin("acknowledge \(events.count) security event(s)")
            try await client.acknowledge(ids: events.map(\.id), admin: admin)
            events = []
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    nonisolated static func postNotification(_ event: SecurityEvent) {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ " + event.title
        content.subtitle = event.repository
        content.body = event.detail
        content.sound = UNNotificationSound.default
        let request = UNNotificationRequest(identifier: "security-\(event.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
