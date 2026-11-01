import AppKit
import SwiftUI

struct RunnerStatePill: View {
    let state: ServiceState
    let text: String

    var body: some View {
        Text(text)
            .font(NothingTheme.tiny.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 19)
            .foregroundStyle(color(for: state))
            .overlay(Capsule().stroke(color(for: state).opacity(0.6), lineWidth: 1))
    }
}

struct RunnerIcon: View {
    let icon: String
    let state: ServiceState

    var body: some View {
        ZStack {
            Circle().stroke(color(for: state).opacity(0.5), lineWidth: 1)
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color(for: state))
        }
    }
}
