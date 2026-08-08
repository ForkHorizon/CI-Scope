import AppKit
import SwiftUI

struct RunnerStatePill: View {
    let state: ServiceState
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 19)
            .background(color(for: state).opacity(0.12))
            .foregroundStyle(color(for: state))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct RunnerIcon: View {
    let icon: String
    let state: ServiceState

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(color(for: state).opacity(0.12))
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color(for: state))
        }
    }
}
