import Foundation

enum WorkspaceTab: String, CaseIterable, Identifiable {
    case projects
    case runners
    case scripts
    case coverage
    case policy
    case tests
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .projects: "Projects"
        case .runners: "Runners"
        case .scripts: "Scripts"
        case .coverage: "Coverage"
        case .policy: "Policy"
        case .tests: "Test protection"
        case .settings: "Settings"
        }
    }
}
