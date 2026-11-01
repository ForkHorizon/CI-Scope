import SwiftUI

struct RunnerMiniMetric: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(NothingTheme.tiny)
                .foregroundStyle(NothingTheme.inkDim)
            Text(value)
                .font(NothingTheme.tiny.monospacedDigit().weight(.semibold))
        }
    }
}

struct RunnerMetric: View {
    let title: String
    let value: String
    let detail: String
    let state: ServiceState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle()
                    .fill(color(for: state))
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(NothingTheme.tiny.weight(.semibold))
                    .lineLimit(1)
            }
            Text(value)
                .font(NothingTheme.small.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(detail)
                .font(NothingTheme.tiny)
                .foregroundStyle(NothingTheme.inkDim)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .nothingCard(radius: 10)
    }
}
