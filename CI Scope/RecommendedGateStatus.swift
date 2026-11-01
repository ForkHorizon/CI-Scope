// How a recommended gate relates to what a repository already has: workflow, Unified Checks manifest, or neither.
import Foundation

enum RecommendedGateStatus: Equatable {
    /// Can be installed as a standalone workflow in one PR.
    case installable
    /// A matching workflow file already exists.
    case installed
    /// The repository's Unified Checks manifest already runs the matching check.
    case inUnifiedChecks
    /// The repository uses Unified Checks but lacks this check; it is added through the Policy tab,
    /// because the manifest is a protected, signed file and a standalone workflow would duplicate it.
    case addViaPolicy

    var isSelectable: Bool { self == .installable }

    var label: String? {
        switch self {
        case .installable: nil
        case .installed: "installed"
        case .inUnifiedChecks: "in unified checks"
        case .addViaPolicy: "add in Policy tab"
        }
    }

    /// Manifest check type that runs the same checks as a seed gate.
    static let manifestCheckTypes = [
        "code-linter": "code-linter",
        "swift-quality-gate": "swift-quality",
        "swift-compile-gate": "swift-compile",
        "web-quality-gate": "web-quality",
        "python-quality-gate": "python-quality",
        "go-quality-gate": "go-quality",
    ]

    /// `manifestTypes` is nil when the repository has no Unified Checks manifest.
    static func status(seedID: String, hasWorkflow: Bool, manifestTypes: Set<String>?) -> Self {
        if hasWorkflow { return .installed }
        guard let manifestTypes else { return .installable }
        if let type = manifestCheckTypes[seedID], manifestTypes.contains(type) { return .inUnifiedChecks }
        return .addViaPolicy
    }
}
