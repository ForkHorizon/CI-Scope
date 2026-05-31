import SwiftUI

struct ScriptsView: View {
    @ObservedObject var store: AutomationScriptStore
    @ObservedObject var installer: AutomationScriptInstallViewModel

    let projects: [CIProject]
    let selectedProject: CIProject?
    let onInstallSuccess: (CIProject) -> Void

    @State private var draft: AutomationScript?
    @State private var originalScriptID: String?
    @State private var selectedProjectID: CIProject.ID?
    @State private var variableValues: [String: String] = [:]
    @State private var errorMessage: String?
    @State private var editorSection: ScriptEditorSection = .details

    var body: some View {
        HStack(spacing: 12) {
            ScriptLibraryList(
                scripts: store.scripts,
                selectedScriptID: store.selectedScriptID,
                canDeleteSelected: store.selectedScript?.defaultSeedID == nil,
                onSelect: select,
                onCreate: createScript,
                onDelete: deleteSelected
            )
            .frame(width: 236)

            if let script = draftBinding {
                ScriptEditorPanel(
                    script: script,
                    section: $editorSection,
                    errorMessage: errorMessage ?? store.errorMessage,
                    onSave: saveDraft,
                    onReset: resetDraft
                )
            } else {
                EmptyState(icon: "curlybraces.square", text: "No script selected")
            }

            ScriptInstallPanel(
                script: draft,
                projects: projects,
                selectedProjectID: $selectedProjectID,
                variableValues: $variableValues,
                snapshot: installer.snapshot(for: draft),
                onInstall: installDraft
            )
            .frame(width: 270)
        }
        .padding(14)
        .onAppear(perform: syncInitialState)
        .onChange(of: store.selectedScriptID) { _, _ in
            syncDraftFromStore()
        }
        .onChange(of: selectedProject?.id) { _, id in
            if selectedProjectID == nil {
                selectedProjectID = id
            }
        }
    }

    private var draftBinding: Binding<AutomationScript>? {
        guard draft != nil else { return nil }
        return Binding(
            get: { draft ?? AutomationScript.empty(uniqueID: "script") },
            set: { draft = $0 }
        )
    }

    private func syncInitialState() {
        selectedProjectID = selectedProjectID ?? selectedProject?.id ?? projects.first?.id
        syncDraftFromStore()
    }

    private func syncDraftFromStore() {
        draft = store.selectedScript
        originalScriptID = draft?.id
        variableValues = defaultValues(for: draft)
        errorMessage = nil
    }

    private func select(_ script: AutomationScript) {
        store.select(script)
        syncDraftFromStore()
    }

    private func createScript() {
        store.createScript()
        syncDraftFromStore()
    }

    private func deleteSelected() {
        store.deleteSelectedScript()
        syncDraftFromStore()
    }

    private func saveDraft() {
        guard let draft else { return }
        do {
            try store.save(draft, replacing: originalScriptID)
            errorMessage = nil
            syncDraftFromStore()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetDraft() {
        do {
            try store.resetSelectedScriptToDefault()
            syncDraftFromStore()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func installDraft() {
        guard let draft else { return }
        do {
            try store.save(draft, replacing: originalScriptID)
            let project = projects.first { $0.id == selectedProjectID }
            installer.install(script: draft, project: project, variableValues: installValues(for: draft)) {
                if let project {
                    onInstallSuccess(project)
                }
            }
            errorMessage = nil
            syncDraftFromStore()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func defaultValues(for script: AutomationScript?) -> [String: String] {
        guard let script else { return [:] }
        return Dictionary(uniqueKeysWithValues: script.variables.map { ($0.id, $0.defaultValue) })
    }

    private func installValues(for script: AutomationScript) -> [String: String] {
        var result = defaultValues(for: script)
        variableValues.forEach { result[$0.key] = $0.value }
        return result
    }
}

enum ScriptEditorSection: String, CaseIterable, Identifiable {
    case details
    case variables
    case files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .details: "Details"
        case .variables: "Variables"
        case .files: "Files"
        }
    }
}
