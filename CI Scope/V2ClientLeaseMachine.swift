import Foundation

public struct V2ClientControlLeaseMachine {
    public private(set) var state: V2ClientControlLeaseState

    public init(state: V2ClientControlLeaseState = .inactive) {
        self.state = state
    }

    public mutating func apply(_ event: V2ClientControlLeaseEvent, now: Date = Date()) throws {
        switch event {
        case .acquired(let controlToken, let expiresAt):
            guard expiresAt > now, !isActive else { throw V2ClientBridgeError.invalidLeaseTransition }
            state = .active(controlToken: controlToken, expiresAt: expiresAt)
        case .renewed(let controlToken, let expiresAt):
            guard case .active(let currentToken, _) = state,
                currentToken == controlToken,
                expiresAt > now
            else { throw V2ClientBridgeError.invalidLeaseTransition }
            state = .active(controlToken: controlToken, expiresAt: expiresAt)
        case .drainRequested(let controlToken, let deadline):
            guard case .active(let currentToken, let expiresAt) = state,
                currentToken == controlToken,
                expiresAt > now,
                deadline >= now
            else { throw V2ClientBridgeError.invalidLeaseTransition }
            state = .draining(controlToken: controlToken, drainDeadline: deadline)
        case .expired:
            state = .expired
        case .released:
            state = .released
        }
    }

    public mutating func expireIfNeeded(at now: Date = Date()) {
        switch state {
        case .active(_, let expiresAt) where expiresAt <= now:
            state = .expired
        case .draining(_, let deadline) where deadline <= now:
            state = .expired
        default:
            break
        }
    }

    private var isActive: Bool {
        if case .active = state { return true }
        return false
    }
}

