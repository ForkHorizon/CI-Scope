import Foundation

struct ReadabilityGateTemplate {
    let destinationPath: String
    let contents: String
}

enum ReadabilityGateTemplates {
    static func load() throws -> [ReadabilityGateTemplate] {
        let root = try sourceRepositoryRoot()
        return try [
            template(".ai-readability.json", root: root),
            template(".github/workflows/ai-readability.yml", root: root),
            template("scripts/ai-readability-check.py", root: root)
        ]
    }

    private static func template(_ path: String, root: URL) throws -> ReadabilityGateTemplate {
        let url = root.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ReadabilityGateInstallerError.missingTemplate(path)
        }
        return ReadabilityGateTemplate(
            destinationPath: path,
            contents: try String(contentsOf: url, encoding: .utf8)
        )
    }

    private static func sourceRepositoryRoot() throws -> URL {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        if hasTemplates(in: sourceRoot) {
            return sourceRoot
        }

        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if hasTemplates(in: currentDirectory) {
            return currentDirectory
        }

        throw ReadabilityGateInstallerError.missingTemplate(".ai-readability.json")
    }

    private static func hasTemplates(in root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(".ai-readability.json").path)
            && FileManager.default.fileExists(atPath: root.appendingPathComponent(".github/workflows/ai-readability.yml").path)
            && FileManager.default.fileExists(atPath: root.appendingPathComponent("scripts/ai-readability-check.py").path)
    }
}

enum ReadabilityGateInstallerError: LocalizedError {
    case commandFailed(step: String, output: String)
    case invalidDefaultBranch(String)
    case missingTemplate(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let step, let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(step) failed.\n\(trimmed.isEmpty ? "No command output." : trimmed)"
        case .invalidDefaultBranch(let slug):
            return "Could not read the default branch for \(slug)."
        case .missingTemplate(let path):
            return "Missing readability gate template: \(path)."
        }
    }
}

func quoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
