import Foundation

enum WorkspaceTab: String, CaseIterable, Identifiable {
    case projects
    case runners
    case localTools
    case scripts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .projects: "Projects"
        case .runners: "Runners"
        case .localTools: "Local Tools"
        case .scripts: "Scripts"
        }
    }

    var icon: String {
        switch self {
        case .projects: "square.grid.2x2"
        case .runners: "server.rack"
        case .localTools: "desktopcomputer"
        case .scripts: "curlybraces.square"
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
