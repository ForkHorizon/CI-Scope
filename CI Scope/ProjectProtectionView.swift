// The Protection section: what the server checks for a project, security events, and the git hooks.
import SwiftUI

struct ProjectProtectionView: View {
    @ObservedObject var model: ProjectProtectionViewModel
    @ObservedObject var events: SecurityEventMonitor
    let projects: [CIProject]
    @State private var selected = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Protection").nothingCaption()
            eventsSection
            projectPicker
            if let config = model.config {
                editor(config)
            } else if !selected.isEmpty, !model.isBusy {
                Button("Register with CI Scope") { Task { await model.register() } }.buttonStyle(.pillPrimary)
            }
            hooksRow
            if let message = model.message ?? events.message {
                Text(message).font(NothingTheme.small).foregroundStyle(NothingTheme.amber).textSelection(.enabled)
            }
        }
        .task {
            await events.refresh()
            await model.refreshHooks()
            if selected.isEmpty, let first = projects.first { selected = first.repositorySlug }
        }
        .task(id: selected) { if !selected.isEmpty { await model.load(repository: selected) } }
    }

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(events.events) { event in
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title).font(NothingTheme.small.weight(.semibold)).foregroundStyle(NothingTheme.red)
                    Text("\(event.repository) · \(event.detail)").font(NothingTheme.tiny).foregroundStyle(NothingTheme.inkDim)
                }
            }
            if !events.events.isEmpty {
                Button("Acknowledge all") { Task { await events.acknowledgeAll() } }.buttonStyle(.pillPrimary)
            }
        }
    }

    private var projectPicker: some View {
        Picker("Project", selection: $selected) {
            ForEach(projects) { Text($0.repositorySlug).tag($0.repositorySlug) }
        }
        .labelsHidden()
    }

    private func editor(_ config: ProjectConfig) -> some View {
        let binding = Binding(get: { model.config ?? config }, set: { model.config = $0 })
        return VStack(alignment: .leading, spacing: 10) {
            Text("Version \(config.version) · \(config.summary)").font(NothingTheme.small).foregroundStyle(NothingTheme.inkDim)
            Toggle("Code rules", isOn: binding.lanes.codeRules.enabled)
            Stepper(
                "Max file lines: \(binding.wrappedValue.lanes.codeRules.params.maxFileLines)",
                value: binding.lanes.codeRules.params.maxFileLines, in: 50...5000, step: 50)
            Stepper(
                "Max function lines: \(binding.wrappedValue.lanes.codeRules.params.maxFunctionLines)",
                value: binding.lanes.codeRules.params.maxFunctionLines, in: 10...500, step: 10)
            Toggle("Forbid lint suppressions in new code", isOn: binding.lanes.codeRules.params.forbidSuppressions)
            Toggle("Agent guard (tests, docs, protected files)", isOn: binding.lanes.agentGuard.enabled)
            Toggle("Merge only when every check is green", isOn: binding.mergeGate.requireGreen)
            Toggle("Delete the branch after merge", isOn: binding.mergeGate.deleteBranchAfterMerge)
            Toggle("Observe only (report, do not block)", isOn: binding.observeOnly)
            Button("Save with Touch ID") { Task { await model.save() } }
                .buttonStyle(.pillPrimary)
                .disabled(model.isBusy)
        }
        .font(NothingTheme.small)
    }

    private var hooksRow: some View {
        HStack {
            Text(hooksText).font(NothingTheme.small).foregroundStyle(NothingTheme.inkDim)
            Spacer()
            if model.hooks == .notInstalled {
                Button("Install git hooks") { Task { await model.installHooks() } }.buttonStyle(.pillPrimary)
            }
        }
    }

    private var hooksText: String {
        switch model.hooks {
        case .installed: "Git hooks installed on this Mac"
        case .notInstalled: "Git hooks are not installed on this Mac"
        case .otherHooksPath(let path): "git already uses \(path) for hooks"
        }
    }
}
