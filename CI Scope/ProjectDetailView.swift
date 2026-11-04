// One project: what the server checks, where to change it (the website), and this Mac's git hooks.
import SwiftUI

struct ProjectDetailView: View {
    let project: CIProject
    @ObservedObject var model: ProjectProtectionViewModel
    @ObservedObject var events: SecurityEventMonitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                protectionSection
                alertsSection
                hooksSection
                if let message = model.message {
                    Text(message).font(NothingTheme.small).foregroundStyle(NothingTheme.amber).textSelection(.enabled)
                }
            }
            .padding(22)
        }
        .task(id: project.repositorySlug) {
            await model.load(repository: project.repositorySlug)
            await model.refreshHooks()
        }
    }

    private var protectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Protection").nothingCaption()
            if let config = model.config {
                Text("Version \(config.version) · \(config.summary)").font(NothingTheme.body).foregroundStyle(NothingTheme.ink)
                Text("Add or change checks on the website. Weakening them needs Touch ID there.")
                    .font(NothingTheme.small).foregroundStyle(NothingTheme.inkDim)
            } else if !model.isBusy {
                Text("\(project.repositorySlug) is not registered with CI Scope yet.").font(NothingTheme.body).foregroundStyle(
                    NothingTheme.inkDim)
            }
            HStack(spacing: 10) {
                if model.config == nil, !model.isBusy {
                    Button("Register with CI Scope") { Task { await model.register(repository: project.repositorySlug) } }
                        .buttonStyle(.pillPrimary)
                }
                Button("Open on website") { NSWorkspace.shared.open(ServerLinks.project(project.repositorySlug)) }
                    .buttonStyle(model.config == nil ? .pill : .pillPrimary)
            }
        }
    }

    private var alertsSection: some View {
        let mine = events.events.filter { $0.repository.caseInsensitiveCompare(project.repositorySlug) == .orderedSame }
        return VStack(alignment: .leading, spacing: 6) {
            Text("Alerts").nothingCaption()
            if mine.isEmpty {
                Text("No open alerts.").font(NothingTheme.small).foregroundStyle(NothingTheme.inkDim)
            }
            ForEach(mine) { event in
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title).font(NothingTheme.small.weight(.semibold)).foregroundStyle(NothingTheme.red)
                    Text(event.detail).font(NothingTheme.tiny).foregroundStyle(NothingTheme.inkDim)
                }
            }
        }
    }

    private var hooksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This Mac").nothingCaption()
            HStack {
                Text(hooksText).font(NothingTheme.small).foregroundStyle(NothingTheme.inkDim)
                Spacer()
                if model.hooks == .notInstalled {
                    Button("Install git hooks") { Task { await model.installHooks() } }.buttonStyle(.pillPrimary)
                }
            }
        }
    }

    private var hooksText: String {
        switch model.hooks {
        case .installed: "Git hooks installed: any agent's commit is checked before it lands"
        case .notInstalled: "Git hooks are not installed on this Mac"
        case .otherHooksPath(let path): "git already uses \(path) for hooks"
        }
    }
}
