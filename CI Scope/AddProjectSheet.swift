import SwiftUI

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
