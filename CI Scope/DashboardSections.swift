import Foundation

enum WorkspaceTab: String, CaseIterable, Identifiable {
    case projects
    case runners
    case scripts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .projects: "Projects"
        case .runners: "Runners"
        case .scripts: "Scripts"
        }
    }

    var icon: String {
        switch self {
        case .projects: "square.grid.2x2"
        case .runners: "server.rack"
        case .scripts: "curlybraces.square"
        }
    }
}
