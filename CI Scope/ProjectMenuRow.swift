import SwiftUI

struct ProjectMenuRow: View {
  let project: CIProject
  let state: ServiceState
  let isActive: Bool
  let onSelect: () -> Void
  let onRemove: () -> Void

  @State var isHovering = false

  var body: some View {
    HStack(spacing: 5) {
      Button {
        onSelect()
      } label: {
        HStack(spacing: 9) {
          ZStack {
            RoundedRectangle(cornerRadius: 6)
              .fill(stateColor.opacity(isActive ? 0.15 : 0.08))
            Image(systemName: "folder")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(isActive ? stateColor : .secondary)
          }
          .frame(width: 31, height: 31)

          VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
              Text(project.title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .lineLimit(1)
              Spacer(minLength: 0)
              StatusDot(state: state)
            }

            Text(project.repositorySlug)
              .font(.caption)
              .foregroundStyle(isActive ? Color.accentColor : .secondary)
              .lineLimit(1)
              .truncationMode(.middle)

            Text(badge)
              .font(.system(size: 10, weight: .semibold, design: .rounded))
              .foregroundStyle(isActive ? Color.accentColor : .secondary)
              .lineLimit(1)
          }
        }
        .padding(.leading, 9)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 8))
      }
      .buttonStyle(.plain)

      Menu {
        ProjectContextMenu(onRemove: onRemove)
      } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(isActive ? Color.accentColor : .secondary)
          .frame(width: 25, height: 25)
          .background(Color.secondary.opacity(isActive || isHovering ? 0.08 : 0.04))
          .clipShape(RoundedRectangle(cornerRadius: 6))
      }
      .buttonStyle(.plain)
      .opacity(isActive || isHovering ? 1 : 0.58)
      .help("Project actions")
    }
    .frame(height: 66)
    .background(isActive ? Color.accentColor.opacity(0.11) : Color(nsColor: .windowBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(isActive ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.12))
    )
    .contentShape(RoundedRectangle(cornerRadius: 8))
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
