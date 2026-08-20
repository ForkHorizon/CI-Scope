import Foundation

enum AutomationScriptError: LocalizedError {
    case commandFailed(step: String, output: String)
    case duplicateScript(String)
    case invalidDefaultBranch(String)
    case invalidValue(String)
    case missingProject
    case missingSeed(String)
    case storage(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let step, let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(step) failed.\n\(trimmed.isEmpty ? "No command output." : trimmed)"
        case .duplicateScript(let id):
            return "A script with id \(id) already exists."
        case .invalidDefaultBranch(let slug):
            return "Could not read the default branch for \(slug)."
        case .invalidValue(let message):
            return message
        case .missingProject:
            return "Choose a project before installing."
        case .missingSeed(let id):
            return "Missing bundled script seed: \(id)."
        case .storage(let message):
            return message
        }
    }
}
