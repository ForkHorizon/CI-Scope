import Foundation

struct BrokerRepoStatus: Identifiable, Codable, Equatable {
    var slug: String
    var state: String
    var queuedCount: Int
    var lastCheckedAt: String
    var lastError: String?
    var profileID: String?
    var profileTitle: String?
    var profileScope: String?
    var labels: [String]?

    var id: String { slug.lowercased() }

    private enum CodingKeys: String, CodingKey {
        case slug
        case state
        case queuedCount
        case lastCheckedAt
        case lastError
        case profileID = "profileId"
        case profileTitle
        case profileScope
        case labels
    }
}

struct BrokerJobProgress: Codable, Equatable {
    var step: String
    var current: Int?
    var total: Int?
    var detail: String?

    var caption: String {
        let counted = (current != nil && total != nil) ? "\(step) \(current!)/\(total!)" : step
        guard let detail, !detail.isEmpty else { return counted }
        return "\(counted) · \(detail)"
    }

    var fraction: Double? {
        guard let current, let total, total > 0 else { return nil }
        return min(max(Double(current) / Double(total), 0), 1)
    }

    var countLabel: String? {
        guard let current, let total, total > 0 else { return nil }
        return "\(current) of \(total)"
    }

    var phaseLabel: String {
        step
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}
