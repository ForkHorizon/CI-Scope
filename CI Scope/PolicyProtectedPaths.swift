import Foundation

/// Mirrors ci-gates `policy_signature_guard.py` DEFAULT_PROTECTED_PATTERNS and the
/// server's `pathAllowed` glob rule (`*` matches across `/`). A PR that changes
/// only these files must come from a `ci-scope/policy/` branch to be activatable.
enum PolicyProtectedPaths {
    static let branchPrefix = "ci-scope/policy/"

    static let defaultPatterns = [
        ".ci-scope.json", ".code-linter.json", "**/.code-linter.json", ".ruff.toml", "**/.ruff.toml",
        "ruff.toml", "**/ruff.toml", ".unity-quality-gate.json", "**/.unity-quality-gate.json",
        ".swift-quality-gate.json", "**/.swift-quality-gate.json", ".slop-review.json",
        "**/.slop-review.json", ".github/workflows/*", ".github/workflows/**", ".github/CODEOWNERS",
        "**/.github/CODEOWNERS", "configs/allowed_signers",
    ]

    static func matches(_ path: String, patterns: [String] = defaultPatterns) -> Bool {
        patterns.contains { pattern in
            path.range(of: regex(for: pattern), options: .regularExpression) != nil
        }
    }

    /// `ci-scope/install-x` becomes `ci-scope/policy/install-x` when every file is protected.
    static func branch(_ name: String, forFiles paths: [String]) -> String {
        guard !paths.isEmpty, paths.allSatisfy({ matches($0) }), !name.hasPrefix(branchPrefix) else {
            return name
        }
        let suffix = name.hasPrefix("ci-scope/") ? String(name.dropFirst("ci-scope/".count)) : name
        return branchPrefix + suffix
    }

    private static func regex(for pattern: String) -> String {
        var result = "^"
        for character in pattern {
            switch character {
            case "*": result += ".*"
            case "?": result += "."
            default: result += NSRegularExpression.escapedPattern(for: String(character))
            }
        }
        return result + "$"
    }
}
