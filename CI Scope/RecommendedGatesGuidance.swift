// Tells the owner what to do when the recommended-gates sheet has nothing to install.
import Foundation

enum RecommendedGatesGuidance: Equatable {
    /// At least one gate can be installed as a standalone workflow.
    case installSelected
    /// Nothing is installable, but the Unified Checks manifest lacks some checks: they are added in the Policy tab.
    case openPolicy
    /// Every recommended gate is already installed or part of the manifest.
    case nothingToDo
    /// No gate matches the repository.
    case nothingDetected

    static func guidance(for statuses: [RecommendedGateStatus]) -> Self {
        if statuses.isEmpty { return .nothingDetected }
        if statuses.contains(where: \.isSelectable) { return .installSelected }
        return statuses.contains(.addViaPolicy) ? .openPolicy : .nothingToDo
    }

    var message: String? {
        switch self {
        case .installSelected: nil
        case .openPolicy:
            "Nothing to install here: this repository uses Unified Checks, so missing checks are added in the Policy tab."
        case .nothingToDo: "Nothing to install: every recommended gate is already in place."
        case .nothingDetected: "No matching gates were detected for this repository."
        }
    }
}
