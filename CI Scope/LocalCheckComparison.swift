import Foundation

/// How the last local `check` relates to the CI run of the same commit.
enum LocalCheckVerdict: Equatable {
    case agree
    case localGreenCIRed
    case localRedCIGreen
    case ciPending
    case ciNotRun
    case unknownCommit

    var isDiscrepancy: Bool { self == .localGreenCIRed || self == .localRedCIGreen }
}

enum LocalCheckComparison {
    static func verdict(local: LocalCheckResult, runs: [GitHubRun]) -> LocalCheckVerdict {
        guard let head = local.gitHead, !head.isEmpty else { return .unknownCommit }
        let sameCommit = runs.filter { $0.headSha == head }
        guard let latest = sameCommit.max(by: { $0.updatedAt < $1.updatedAt }) else { return .ciNotRun }
        guard let conclusion = latest.conclusion else { return .ciPending }
        let ciGreen = conclusion == "success"
        switch (local.passed, ciGreen) {
        case (true, true), (false, false): return .agree
        case (true, false): return .localGreenCIRed
        case (false, true): return .localRedCIGreen
        }
    }
}
