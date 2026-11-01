import AppKit
import SwiftUI

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
