import Foundation

@MainActor
extension AutomationScriptStore {
    /// Titles the Code Linter shipped under before 2026-08-08. The title drives
    /// `scriptSlug`, which drives every path the gate installs, so a stored
    /// script left on an old title keeps writing the old filenames.
    static let preCodeLinterTitles: Set<String> = [
        "AI Readability Gate",
        "AI readability gate",
        "300-line linter gate",
        "Linter Checker 300 Lines",
        "Linter Checker 300 lines",
        "Code Structure Linter",
    ]

    /// The seed id was `ai-readability` until the gate settled on Code Linter.
    /// `id` is the store's filename, so it is left alone; `defaultSeedID` is the
    /// link to the seed and has to follow the rename or the script stops
    /// matching any seed and silently drops out of migrations.
    func migratedCodeLinterRename(_ script: AutomationScript) -> AutomationScript {
        var migrated = script
        if migrated.defaultSeedID == "ai-readability" {
            migrated.defaultSeedID = "code-linter"
        }
        guard migrated.defaultSeedID == "code-linter" else { return migrated }
        if Self.preCodeLinterTitles.contains(migrated.title.trimmed) {
            migrated.title = "Code Linter"
        }
        return migrated
    }
}
