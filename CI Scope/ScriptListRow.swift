import SwiftUI

struct ScriptListRow: View {
    let script: AutomationScript
    let isSelected: Bool
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
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "curlybraces.square")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isExpanded ? NothingTheme.ink : .secondary)
                        .frame(width: 24, height: 24)

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
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(NothingTheme.inkDim)
                        .frame(width: 16, height: 24)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
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
            }
        }
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(rowBorder)
        )
    }

    private var rowBackground: Color {
        if isExpanded { return NothingTheme.ink.opacity(0.10) }
        if isSelected { return NothingTheme.ink.opacity(0.06) }
        return Color.secondary.opacity(0.055)
    }

    private var rowBorder: Color {
        if isExpanded { return NothingTheme.ink.opacity(0.34) }
        if isSelected { return NothingTheme.ink.opacity(0.18) }
        return Color.secondary.opacity(0.10)
    }
}
