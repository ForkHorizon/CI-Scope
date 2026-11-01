import AppKit
import SwiftUI

struct RunnerQueueTimeline: View {
    let title: String
    let emptyText: String
    let items: [RunnerWorkItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(NothingTheme.body.weight(.semibold))
                Spacer()
                Text("\(items.count)")
                    .font(NothingTheme.small.monospacedDigit())
                    .foregroundStyle(NothingTheme.inkDim)
            }

            if items.isEmpty {
                RunnerWorkEmptyRow(text: emptyText)
            } else {
                ForEach(items.prefix(5)) { item in
                    RunnerWorkRow(item: item)
                }

                if items.count > 5 {
                    Text("+\(items.count - 5) more")
                        .font(NothingTheme.small)
                        .foregroundStyle(NothingTheme.inkDim)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }
}

struct RunnerWorkEmptyRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(text == "Busy, job not visible yet" ? .orange : .secondary)
            Text(text)
                .font(NothingTheme.small)
                .foregroundStyle(NothingTheme.inkDim)
            Spacer()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var icon: String {
        text == "Idle" || text == "No queued jobs" ? "checkmark.circle" : "clock"
    }
}
