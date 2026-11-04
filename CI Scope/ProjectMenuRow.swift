import SwiftUI

struct ProjectMenuRow: View {
    let project: CIProject
    let state: ServiceState
    let isActive: Bool
    let onSelect: () -> Void

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
                            .font(.system(size: 11, design: .monospaced))
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

        }
        .frame(height: 44)
        .background(isActive ? NothingTheme.ink : (isHovering ? NothingTheme.panel : Color.clear), in: Capsule())
        .contentShape(Capsule())
        .onHover { isHovering = $0 }
        .pointerStyle(.link)
        .animation(.smooth(duration: 0.18), value: isHovering)
        .animation(.smooth(duration: 0.25), value: isActive)
    }

}
