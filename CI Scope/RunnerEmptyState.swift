import AppKit
import SwiftUI

struct RunnerEmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "server.rack")
                .font(.title3)
                .foregroundStyle(NothingTheme.inkDim)
            Text("No runner loaded")
                .font(NothingTheme.small)
                .foregroundStyle(NothingTheme.inkDim)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}
