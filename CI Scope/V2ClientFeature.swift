import Foundation

enum V2ClientAuthorityState: String, Codable, CaseIterable {
    case legacyBroker
    case v2ReadOnly
    case v2Authority

    var displayName: String {
        switch self {
        case .legacyBroker:
            return "Legacy broker authoritative"
        case .v2ReadOnly:
            return "V2 read-only"
        case .v2Authority:
            return "V2 authority enabled"
        }
    }

    var allowsMutation: Bool {
        self == .v2Authority
    }
}

enum V2ClientFeature {
    static let statusAdapterKey = "ciScope.v2.statusAdapter.enabled"
    static let explicitAuthorityEnabledKey = "ciScope.v2.authority.explicitlyEnabled"
    static let authorityStateKey = "ciScope.v2.authority.state"
    static let authorityReleasePendingKey = "ciScope.v2.authority.releasePending"
    static let socketPathKey = "ciScope.v2.agent.socketPath"
    static let bootIDKey = "ciScope.v2.agent.bootID"
    static let agentInstanceIDKey = "ciScope.v2.agent.instanceID"
    static let sessionIDKey = "ciScope.v2.agent.sessionID"
    static let sessionEpochKey = "ciScope.v2.agent.sessionEpoch"
    static let localOwnerEpochKey = "ciScope.v2.agent.localOwnerEpoch"
    static let fencingTokenKey = "ciScope.v2.agent.fencingToken"

    static func statusAdapterEnabled(defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: statusAdapterKey) != nil {
            return defaults.bool(forKey: statusAdapterKey)
        }
        return FileManager.default.fileExists(atPath: V2ClientAgentSessionDescriptor.url.path)
    }

    static func authorityState(defaults: UserDefaults = .standard) -> V2ClientAuthorityState {
        guard statusAdapterEnabled(defaults: defaults) else { return .legacyBroker }
        guard defaults.string(forKey: authorityStateKey) == V2ClientAuthorityState.v2Authority.rawValue else {
            return .v2ReadOnly
        }
        return .v2Authority
    }
}
