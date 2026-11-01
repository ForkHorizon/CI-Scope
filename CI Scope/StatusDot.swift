import SwiftUI

/// Nothing-style status dot: filled white = online, red = attention, hollow = unknown.
struct StatusDot: View {
    let state: ServiceState
    var onLight = false

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: 8, height: 8)
            .overlay(Circle().stroke(stroke, lineWidth: 1))
            .help(state.rawValue)
    }

    private var fill: Color {
        switch state {
        case .online: NothingTheme.green
        case .warning: NothingTheme.amber
        case .offline: NothingTheme.red
        case .unknown: .clear
        }
    }

    private var stroke: Color {
        switch state {
        case .online: NothingTheme.green
        case .warning: NothingTheme.amber
        case .offline: NothingTheme.red
        case .unknown: onLight ? Color.black.opacity(0.4) : NothingTheme.lineStrong
        }
    }
}
