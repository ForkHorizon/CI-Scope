import SwiftUI

struct ScriptListRow: View {
    let script: AutomationScript
    let isExpanded: Bool
    let projects: [CIProject]
    @Binding var selectedProjectID: CIProject.ID?
    @Binding var runnerMode: AutomationScriptInstallMode
    @Binding var variableValues: [String: String]
    let snapshot: AutomationScriptInstallSnapshot
    let onSelect: () -> Void
    let onOpenEditor: () -> Void
    let onInstall: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onSelect) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(script.title)
                                .font(NothingTheme.body.weight(.semibold))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(script.files.count == 1 ? "1 file" : "\(script.files.count) files")
                                .font(NothingTheme.tiny.monospacedDigit())
                                .foregroundStyle(NothingTheme.inkDim)
                        }

                        Text(script.summary)
                            .font(NothingTheme.small)
                            .foregroundStyle(NothingTheme.inkDim)
                            .lineLimit(2)

                        if !script.detail.trimmed.isEmpty {
                            Text(script.detail)
                                .font(NothingTheme.tiny)
                                .foregroundStyle(NothingTheme.inkDim)
                                .lineLimit(2)
                        }
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11))
                        .foregroundStyle(NothingTheme.inkDim)
                        .frame(width: 16, height: 24)
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ScriptInstallSubmenu(
                    script: script,
                    projects: projects,
                    selectedProjectID: $selectedProjectID,
                    runnerMode: $runnerMode,
                    variableValues: $variableValues,
                    snapshot: snapshot,
                    onOpenEditor: onOpenEditor,
                    onInstall: onInstall
                )
                .nothingCard(radius: 14, highlighted: true)
                .padding(.bottom, 12)
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(NothingTheme.line).frame(height: 1) }
    }
}
