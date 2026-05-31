import SwiftUI

struct LocalToolsHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            Label("Local Tools", systemImage: "desktopcomputer")
                .font(.caption.weight(.semibold))
            Text("Configured runner and editor services")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 2)
    }
}

struct StatusTile: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let state: ServiceState

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(stateColor.opacity(0.12))
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(stateColor)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                    StatusDot(state: state)
                }
                Text(value)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(height: 70)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.13))
        )
    }

    var stateColor: Color {
        switch state {
        case .online: .green
        case .warning: .orange
        case .offline: .red
        case .unknown: .secondary
        }
    }
}

struct CommandStrip: View {
    @ObservedObject var runner: LocalCommandRunner

    var body: some View {
        VStack(spacing: 9) {
            HStack {
                Label("Local Commands", systemImage: "bolt.horizontal")
                    .font(.caption.weight(.semibold))
                Spacer()
                if runner.isRunning {
                    ProgressView()
                        .controlSize(.small)
                    Text(runner.activeTitle ?? "Running")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button(role: .destructive) {
                        runner.stop()
                    } label: {
                        Image(systemName: "stop.fill")
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help("Stop")
                } else if let code = runner.lastExitCode {
                    Text("Exit \(code)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(code == 0 ? .green : .red)
                }
            }

            HStack(spacing: 7) {
                ForEach(LocalCommandPreset.allCases) { preset in
                    CommandButton(preset: preset, runner: runner)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.13))
        )
    }
}

struct CommandButton: View {
    let preset: LocalCommandPreset
    @ObservedObject var runner: LocalCommandRunner

    var body: some View {
        Button {
            runner.run(preset)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: preset.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(preset.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 45)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.secondary.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .disabled(runner.isRunning)
        .opacity(runner.isRunning ? 0.48 : 1)
        .help(preset.title)
    }
}
