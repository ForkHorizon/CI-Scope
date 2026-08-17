import Foundation

public enum V2ClientControlLeaseState: Codable, Equatable {
    case inactive
    case active(controlToken: String, expiresAt: Date)
    case draining(controlToken: String, drainDeadline: Date)
    case expired
    case released

    public var isDraining: Bool {
        if case .draining = self { return true }
        return false
    }

    public func canClaim(at now: Date) -> Bool {
        guard case .active(_, let expiresAt) = self else { return false }
        return expiresAt > now
    }
}

public enum V2ClientControlLeaseEvent {
    case acquired(controlToken: String, expiresAt: Date)
    case renewed(controlToken: String, expiresAt: Date)
    case drainRequested(controlToken: String, deadline: Date)
    case expired
    case released
}

