import SwiftUI

struct ProjectScriptRemovalList: View {
    let scripts: [AutomationScript]
    let snapshot: (AutomationScript) -> AutomationScriptInstallSnapshot
    let onRemove: (AutomationScript) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Library Scripts")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(scripts) { script in
                ProjectScriptRemovalRow(
                    script: script,
                    snapshot: snapshot(script)
                ) {
                    onRemove(script)
                }
            }
        }
    }
}

struct ProjectScriptRemovalRow: View {
    let script: AutomationScript
    let snapshot: AutomationScriptInstallSnapshot
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                StatusDot(state: rowState)
                VStack(alignment: .leading, spacing: 2) {
                    Text(script.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(script.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button(role: .destructive, action: onRemove) {
                    Label(snapshot.isInstalling ? "Removing" : "Remove", systemImage: "trash")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .disabled(snapshot.isInstalling)
            }

            if snapshot != .idle {
                AutomationScriptInstallStatusBox(status: snapshot)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var rowState: ServiceState {
        snapshot == .idle ? .unknown : snapshot.state
    }
}
