import AppKit
import SwiftUI

struct LiveWorkCard: View {
    let item: RunnerWorkItem
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 11) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.14))
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: compact ? 13 : 15, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: compact ? 30 : 36, height: compact ? 30 : 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.repositorySlug)
                        .font(compact ? .caption.weight(.semibold) : .callout.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(item.workflowName) · \(item.jobName)")
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

            progressBody

            Text("\(item.title) · \(item.headBranch)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(compact ? 10 : 13)
        .background(Color.accentColor.opacity(compact ? 0.055 : 0.075))
        .clipShape(RoundedRectangle(cornerRadius: compact ? 8 : 10))
        .overlay(RoundedRectangle(cornerRadius: compact ? 8 : 10).stroke(Color.accentColor.opacity(0.22)))
    }

    @ViewBuilder
    private var progressBody: some View {
        if let progress = item.progress {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(progress.phaseLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Spacer(minLength: 6)
                    Text(progress.countLabel ?? "In progress")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(progress.countLabel == nil ? .secondary : .primary)
                }

                if let fraction = progress.fraction {
                    ProgressView(value: fraction).tint(Color.accentColor)
                } else {
                    ProgressView().controlSize(.small)
                }

                if let detail = progress.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(compact ? 1 : 2)
                        .truncationMode(.middle)
                }
            }
        } else {
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text("Job is starting — waiting for the first live update")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct RunnerBusyWorkCard: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text("Job is starting").font(.callout.weight(.semibold))
                Text("Waiting for GitHub to publish the job details.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}
