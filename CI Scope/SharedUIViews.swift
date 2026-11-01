import AppKit
import SwiftUI

struct PanelShell<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).nothingCaption()
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Rectangle().fill(NothingTheme.line).frame(height: 1)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyState: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(NothingTheme.inkDim)
            Text(text)
                .font(NothingTheme.small)
                .foregroundStyle(NothingTheme.inkDim)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}

#Preview {
    ContentView()
}
