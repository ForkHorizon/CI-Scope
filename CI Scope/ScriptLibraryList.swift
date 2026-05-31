import SwiftUI

struct ScriptLibraryList: View {
    let scripts: [AutomationScript]
    let selectedScriptID: AutomationScript.ID?
    let canDeleteSelected: Bool
    let onSelect: (AutomationScript) -> Void
    let onCreate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        PanelShell(title: "Scripts Library", icon: "curlybraces.square") {
            VStack(spacing: 8) {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(scripts) { script in
                            ScriptLibraryRow(
                                script: script,
                                isActive: script.id == selectedScriptID
                            ) {
                                onSelect(script)
                            }
                        }
                    }
                    .padding(10)
                }

                HStack(spacing: 7) {
                    Button(action: onCreate) {
                        Label("New", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    Button(action: onDelete) {
                        Label("Delete", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!canDeleteSelected)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .padding([.horizontal, .bottom], 10)
            }
        }
    }
}

struct ScriptLibraryRow: View {
    let script: AutomationScript
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9) {
                Image(systemName: "curlybraces.square")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(script.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(script.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(9)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        }
        .buttonStyle(.plain)
        .background(isActive ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(isActive ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.1))
        )
    }
}
