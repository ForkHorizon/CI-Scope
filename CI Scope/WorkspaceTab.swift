// The three places the app has: a project's protection, the open alerts, and this Mac's settings.
import Foundation

enum WorkspaceTab: String, CaseIterable, Identifiable {
    case projects
    case alerts
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .projects: "Projects"
        case .alerts: "Alerts"
        case .settings: "Settings"
        }
    }
}
