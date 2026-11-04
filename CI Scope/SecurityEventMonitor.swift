// Polls the server for security events, raises a toast for each new one, and acknowledges them on request.
import Combine
import Foundation

@MainActor
final class SecurityEventMonitor: ObservableObject {
    @Published private(set) var events: [SecurityEvent] = []
    @Published var message: String?

    var client = SecurityEventsClient()
    var readToken: () async throws -> String = { try await ServerAuthorizer.configReadToken() }
    var adminLogin: (String) async throws -> (user: String, password: String) = { reason in
        try await ServerAuthorizer.adminLogin(reason: reason)
    }
    var notify: (SecurityEvent) -> Void = { event in
        ToastCenter.shared.post(Toast(kind: .alert, title: event.title, detail: "\(event.repository) · \(event.detail)", destination: .alerts))
    }

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
}
