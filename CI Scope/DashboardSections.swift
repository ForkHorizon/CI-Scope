import Foundation

enum WorkspaceTab: String, CaseIterable, Identifiable {
    case projects
    case runners

    var id: String { rawValue }

    var title: String {
        switch self {
        case .projects: "Projects"
        case .runners: "Runners"
        }
    }

    var icon: String {
        switch self {
        case .projects: "square.grid.2x2"
        case .runners: "server.rack"
        }
    }
}

enum DashboardSection: String, CaseIterable, Identifiable {
    case runs
    case logs
    case scripts
    case console

    var id: String { rawValue }

    var title: String {
        switch self {
        case .runs: "Runs"
        case .logs: "Logs"
        case .scripts: "Scripts"
        case .console: "Console"
        }
    }

    var icon: String {
        switch self {
        case .runs: "point.3.connected.trianglepath.dotted"
        case .logs: "doc.text.magnifyingglass"
        case .scripts: "curlybraces.square"
        case .console: "terminal"
        }
    }
}
