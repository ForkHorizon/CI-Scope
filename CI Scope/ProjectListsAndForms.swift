import SwiftUI

struct ProjectWorkflowList: View {
    let workflows: [GitHubWorkflow]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Workflows")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(workflows) { workflow in
                HStack(spacing: 8) {
                    StatusDot(state: workflow.state.lowercased().contains("disabled") ? .warning : .online)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workflow.name)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        Text(workflow.path ?? workflow.state)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Text(workflow.state)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(Color.secondary.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
        }
    }
}

struct ProjectRunList: View {
    let runs: [GitHubRun]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Recent Runs")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(runs.prefix(8)) { run in
                Link(destination: URL(string: run.url)!) {
                    RunRow(run: run)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ErrorBox: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.monospaced())
            .foregroundStyle(.red)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(9)
            .background(Color.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.red.opacity(0.18))
            )
        }
}

struct LimitedStatusRow: View {
    let title: String
    let value: String
    let icon: String
    let state: ServiceState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
            StatusDot(state: state)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Color.secondary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

struct AddProjectSheet: View {
    @Environment(\.dismiss) var dismiss
    @State var input = ""
    @State var errorMessage: String?

    let onAdd: (String) throws -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Add Project", systemImage: "plus")
                    .font(.headline)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Git repository URL")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("git@github.com:owner/repo.git", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Add Project") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 420)
    }

    func submit() {
        do {
            try onAdd(input)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct EmptyProjectDashboard: View {
    let onAddProject: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)

            Image(systemName: "folder.badge.plus")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text("No project selected")
                    .font(.headline)
                Text("Add a repository to monitor its CI.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button {
                onAddProject()
            } label: {
                Label("Add Project", systemImage: "plus")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Color.accentColor.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .help("Add Project")

            Spacer(minLength: 0)
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
