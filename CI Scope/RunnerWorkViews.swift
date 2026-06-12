import AppKit
import SwiftUI

struct RunnerWorkSection: View {
    let title: String
    let emptyText: String
    let items: [RunnerWorkItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.callout.weight(.semibold))
                Spacer()
                Text("\(items.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if items.isEmpty {
                RunnerWorkEmptyRow(text: emptyText)
            } else {
                ForEach(items.prefix(5)) { item in
                    RunnerWorkRow(item: item)
                }

                if items.count > 5 {
                    Text("+\(items.count - 5) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }
}

private struct RunnerWorkEmptyRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(text == "Busy, job not visible yet" ? .orange : .secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
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

private struct RunnerWorkRow: View {
    let item: RunnerWorkItem

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(item.status == "queued" ? Color.orange : Color.green)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.repositorySlug)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(item.status)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let assemblerTitle = item.assemblerTitle {
                        Text(assemblerTitle)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, 5)
                            .frame(height: 16)
                            .background(Color.accentColor.opacity(0.1))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .help(item.assemblerScope ?? assemblerTitle)
                    }
                }

                Text("\(item.workflowName) · \(item.jobName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("\(item.title) · \(item.headBranch)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if let url = URL(string: item.url), !item.url.isEmpty {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Open GitHub job")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

struct RunnerLabelStrip: View {
    let labels: [String]

    var body: some View {
        if !labels.isEmpty {
            HStack(spacing: 5) {
                ForEach(labels.prefix(8), id: \.self) { label in
                    Text(label)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(Color.secondary.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }

                if labels.count > 8 {
                    Text("+\(labels.count - 8)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

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

struct RunnerWarningLine: View {
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(text)
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(2)
            Spacer()
        }
        .padding(8)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}
