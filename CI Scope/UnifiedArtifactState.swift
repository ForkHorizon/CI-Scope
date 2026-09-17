import Foundation

enum UnifiedArtifactState: Equatable {
    case pending
    case available(name: String)
    case missing
    case expired
    case invalid(String)

    var description: String {
        switch self {
        case .pending: "Report pending"
        case .available: "Report available"
        case .missing: "Results unavailable"
        case .expired: "Report expired"
        case .invalid(let reason): "Invalid report: \(reason)"
        }
    }
}
