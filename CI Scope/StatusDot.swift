import SwiftUI

/// Nothing-style status dot: filled white = online, red = attention, hollow = unknown.
struct StatusDot: View {
    let state: ServiceState
    var onLight = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pulses: Bool { (state == .warning || state == .offline) && !reduceMotion }

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: 8, height: 8)
            .overlay(Circle().stroke(stroke, lineWidth: 1))
            .overlay {
                if pulses {
                    Loop(period: state == .offline ? 1.0 : 1.7) { phase in
                        Circle().stroke(stroke, lineWidth: 1).scaleEffect(1 + phase * 1.6).opacity(0.8 * (1 - phase))
                    }
                }
            }
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
