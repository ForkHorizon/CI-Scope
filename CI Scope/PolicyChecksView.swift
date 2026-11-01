import SwiftUI

/// Toggle checks in a repo's trusted `.ci-scope.json`. Toggles only stage the edit;
/// Apply asks for Touch ID once, then opens, merges and activates the policy PR.
struct PolicyChecksView: View {
    @ObservedObject var viewModel: PolicyChecksViewModel
    @ObservedObject var admin: PolicyAdminViewModel
    let projects: [CIProject]
    @State private var projectID: CIProject.ID?

    private var project: CIProject? {
        projects.first { $0.id == projectID } ?? projects.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Checks", systemImage: "checklist")
                .font(.callout.weight(.semibold))
            HStack {
                Picker("Project", selection: $projectID) {
                    ForEach(projects) { Text($0.repositorySlug).tag(Optional($0.id)) }
                }
                Picker("Branch", selection: $viewModel.branch) {
                    ForEach(PolicyChecksViewModel.branches, id: \.self) { Text($0).tag($0) }
                }
                .frame(maxWidth: 180)
            }
            content
            footer
        }
        .padding(10)
        .background(Color.secondary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear { projectID = projectID ?? projects.first?.id }
        .task(id: "\(project?.id ?? "")|\(viewModel.branch)") {
            if let project { await viewModel.load(project) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error = viewModel.loadError {
            Text(error).font(.caption).foregroundStyle(.secondary)
        } else if viewModel.original == nil {
            ProgressView().controlSize(.small)
        } else {
            ForEach(viewModel.rows, id: \.self) { id in
                Toggle(
                    id,
                    isOn: Binding(
                        get: { viewModel.checkIDs.contains(id) },
                        set: { viewModel.toggle(id, on: $0) }
                    )
                )
                .font(.caption.monospaced())
                .disabled(viewModel.isBusy)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if viewModel.hasChanges {
                Text("Pending: \(viewModel.summary)")
                    .font(.caption.weight(.semibold))
            }
            HStack {
                Button("Apply with Touch ID") {
                    guard let project else { return }
                    Task { await viewModel.apply(to: project, admin: admin) }
                }
                .disabled(!viewModel.hasChanges || viewModel.isBusy || admin.isApproving)
                Button("Discard") { viewModel.discard() }
                    .disabled(!viewModel.hasChanges || viewModel.isBusy)
                if viewModel.isBusy { ProgressView().controlSize(.small) }
            }
            if let message = viewModel.message {
                Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }
}
