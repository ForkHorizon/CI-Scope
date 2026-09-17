import Foundation

struct UnifiedChecksSnapshot {
    let manifest: CIScopeManifest
    let run: GitHubRun?
    let report: UnifiedChecksReport?
    let artifact: UnifiedArtifactState
}

enum UnifiedChecksError: LocalizedError {
    case unsupportedManifestVersion
    case emptyManifest
    case duplicateCheckID
    case unsupportedReportVersion
    case reportTooLarge
    case reportIdentityMismatch

    var errorDescription: String? {
        switch self {
        case .unsupportedManifestVersion: "Unsupported .ci-scope.json version."
        case .emptyManifest: ".ci-scope.json contains no checks."
        case .duplicateCheckID: ".ci-scope.json contains duplicate check IDs."
        case .unsupportedReportVersion: "Unsupported result.json version."
        case .reportTooLarge: "result.json exceeds 64 KiB."
        case .reportIdentityMismatch: "Report identity does not match the GitHub run."
        }
    }
}
