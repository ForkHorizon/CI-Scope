import SwiftUI

struct ProjectScriptRemovalList: View {
    let installedScripts: [InstalledAutomationScript]
    let snapshot: (AutomationScript) -> AutomationScriptInstallSnapshot
    let onRemove: (AutomationScript) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Installed Scripts").nothingCaption()

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
                        .font(NothingTheme.body.weight(.semibold))
                        .lineLimit(1)
                    Text(installedScript.detail)
                        .font(NothingTheme.small)
                        .foregroundStyle(NothingTheme.inkDim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button(snapshot.isInstalling ? "Removing" : "Remove", action: onRemove)
                    .buttonStyle(.pillDanger)
                    .disabled(snapshot.isInstalling)
            }

            if snapshot != .idle {
                AutomationScriptInstallStatusBox(status: snapshot)
            }
        }
        .nothingRow()
    }

    private var rowState: ServiceState {
        snapshot == .idle ? installedScript.state : snapshot.state
    }
}
