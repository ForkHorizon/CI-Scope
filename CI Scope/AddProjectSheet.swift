import SwiftUI

struct AddProjectSheet: View {
    @Environment(\.dismiss) var dismiss
    @State var input = ""
    @State var errorMessage: String?

    let onAdd: (String) throws -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add project").nothingDisplay(24)

            VStack(alignment: .leading, spacing: 6) {
                Text("Git repository URL").nothingCaption()
                TextField("git@github.com:owner/repo.git", text: $input)
                    .nothingField()
                    .onSubmit(submit)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(NothingTheme.small)
                    .foregroundStyle(NothingTheme.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.pill)
                .keyboardShortcut(.cancelAction)

                Button("Add project") {
                    submit()
                }
                .buttonStyle(.pillPrimary)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 440)
        .background(NothingTheme.canvas)
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

            VStack(spacing: 6) {
                Text("No project selected").nothingDisplay(26)
                Text("Add a repository to monitor its CI.")
                    .font(NothingTheme.body)
                    .foregroundStyle(NothingTheme.inkDim)
            }

            Button("Add project", action: onAddProject)
                .buttonStyle(.pillPrimary)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

    }
}
