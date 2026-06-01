import SwiftUI

struct ProjectScriptRemovalList: View {
    let installedScripts: [InstalledAutomationScript]
    let snapshot: (AutomationScript) -> AutomationScriptInstallSnapshot
    let onRemove: (AutomationScript) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Installed Scripts")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(installedScripts) { installedScript in
                ProjectScriptRemovalRow(
                    installedScript: installedScript,
                    snapshot: snapshot(installedScript.script)
                ) {
                    onRemove(installedScript.script)
                }
            }
        }
    }
}

struct ProjectScriptRemovalRow: View {
    let installedScript: InstalledAutomationScript
    let snapshot: AutomationScriptInstallSnapshot
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                StatusDot(state: rowState)
                VStack(alignment: .leading, spacing: 2) {
                    Text(installedScript.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(installedScript.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
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
        snapshot == .idle ? installedScript.state : snapshot.state
    }
}
