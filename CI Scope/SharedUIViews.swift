import AppKit
import SwiftUI

struct FileOpenButton: View {
    let title: String
    let path: String?
    var icon = "folder"

    var body: some View {
        Button {
            reveal()
        } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .labelStyle(.iconOnly)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.38)
        .help(isAvailable ? "Open \(title)" : "\(title) file unavailable")
    }

    var isAvailable: Bool {
        guard let path else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    func reveal() {
        guard let path, isAvailable else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

struct PanelShell<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.caption.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.055))
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.13))
        )
    }
}

struct LogScroll: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.12))
        )
    }
}

struct EmptyState: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}

struct StatusDot: View {
    let state: ServiceState

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay {
                Circle()
                    .stroke(color.opacity(0.35), lineWidth: 3)
            }
            .help(state.rawValue)
    }

    var color: Color {
        switch state {
        case .online: .green
        case .warning: .orange
        case .offline: .red
        case .unknown: .secondary
        }
    }
}

#Preview {
    ContentView()
}
