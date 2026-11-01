import SwiftUI

struct ProjectMenuRow: View {
    let project: CIProject
    let state: ServiceState
    let isActive: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void

    @State var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onSelect) {
                HStack(spacing: 10) {
                    StatusDot(state: state, onLight: isActive)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.title)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                        Text(project.repositorySlug)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(isActive ? Color.black.opacity(0.55) : NothingTheme.inkDim)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(isActive ? Color.black : NothingTheme.ink)
                .padding(.leading, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                ProjectContextMenu(onRemove: onRemove)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12))
                    .foregroundStyle(isActive ? Color.black : NothingTheme.inkDim)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(isActive || isHovering ? 1 : 0)
            .help("Project actions")
            .padding(.trailing, 6)
        }
        .frame(height: 44)
        .background(isActive ? NothingTheme.ink : (isHovering ? NothingTheme.panel : Color.clear), in: Capsule())
        .contentShape(Capsule())
        .contextMenu {
            ProjectContextMenu(onRemove: onRemove)
        }
        .onHover { isHovering = $0 }
    }

    var badge: String {
        if isActive { return "Active" }
        return "Saved"
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

struct ProjectContextMenu: View {
    let onRemove: () -> Void

    var body: some View {
        Button(role: .destructive) {
            onRemove()
        } label: {
            Label("Remove Project", systemImage: "trash")
        }
    }
}
