import Foundation

/// Paths a gate used to install under, kept so a renamed gate still recognises —
/// and cleans up — an older installation.
///
/// The destination paths are templated on `{{script_slug}}`, which is derived
/// from the script's title. Renaming a gate therefore moves every file it owns,
/// so without this table the app reads a repo that already has the gate as "not
/// installed" and a reinstall leaves the previous workflow behind, running twice.
enum AutomationScriptLegacyPaths {
    static let bySeedID: [String: [String]] = [
        "ai-readability": [
            ".ai-readability.json",
            ".github/workflows/ai-readability.yml",
            "scripts/ai-readability-check.py",
            // Title was "Linter Checker 300 Lines" until 2026-08-07.
            ".linter-checker-300-lines.json",
            ".github/workflows/linter-checker-300-lines.yml",
            // …then "Code Structure Linter" for a day, before settling on "Code Linter".
            ".code-structure-linter.json",
            ".github/workflows/code-structure-linter.yml",
        ]
    ]

    static func paths(forSeedID seedID: String?) -> [String] {
        guard let seedID else { return [] }
        return bySeedID[seedID] ?? []
    }
}

extension AutomationScript {
    var legacyInstallPaths: [String] {
        let seedID = defaultSeedID ?? id
        return AutomationScriptLegacyPaths.paths(forSeedID: seedID)
    }
}
