import SwiftUI

/// Nothing-style status dot: filled white = online, red = attention, hollow = unknown.
struct StatusDot: View {
    let state: ServiceState
    var onLight = false
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pulses: Bool { (state == .warning || state == .offline) && !reduceMotion }

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: 8, height: 8)
            .overlay(Circle().stroke(stroke, lineWidth: 1))
            .overlay {
                if pulses { Circle().stroke(stroke, lineWidth: 1).scaleEffect(pulse ? 2.6 : 1).opacity(pulse ? 0 : 0.8) }
            }
            .task(id: state) {
                pulse = false
                guard pulses else { return }
                try? await Task.sleep(for: .milliseconds(30))
                withAnimation(.easeOut(duration: state == .offline ? 1.0 : 1.7).repeatForever(autoreverses: false)) { pulse = true }
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
