// The places the app has: a project's protection, the agent's activity, the open alerts, and this Mac's settings.
import Foundation

enum WorkspaceTab: String, CaseIterable, Identifiable {
    case projects
    case activity
    case alerts
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .projects: "Projects"
        case .activity: "Activity"
        case .alerts: "Alerts"
        case .settings: "Settings"
        }
    }
}
