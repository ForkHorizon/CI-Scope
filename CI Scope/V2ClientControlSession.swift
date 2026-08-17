import Combine
import Foundation

@MainActor
final class V2ClientControlSession: ObservableObject {
    @Published var leaseState: V2ClientControlLeaseState = .inactive
    @Published var statusProjection: V2ClientStatusProjection?
    @Published var lastError: String?
    @Published var isWorking = false
    @Published var explicitAuthorityEnabled = false
    @Published var isAgentLive = false
    @Published var lastStatusAt: Date?
    @Published var isDisablingAuthority = false

    let defaults: UserDefaults
    var leaseMachine = V2ClientControlLeaseMachine()
    var renewalTask: Task<Void, Never>?
    var statusTask: Task<Void, Never>?
    var adapter: V2ClientStatusAdapter?
    var authorityReleasePending: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        explicitAuthorityEnabled = defaults.bool(forKey: V2ClientFeature.explicitAuthorityEnabledKey)
        authorityReleasePending = defaults.bool(forKey: V2ClientFeature.authorityReleasePendingKey)
        isDisablingAuthority = authorityReleasePending
        configure()
    }

    var authorityState: V2ClientAuthorityState {
        Self.effectiveAuthorityState(
            explicitAuthorityEnabled: explicitAuthorityEnabled,
            leaseState: leaseState,
            releasePending: authorityReleasePending
        )
    }

    var isConfigured: Bool { adapter != nil }
    var hasActiveLease: Bool { activeLease != nil }
    var hasLeaseToRelease: Bool {
        switch leaseState {
        case .active, .draining:
            return true
        case .inactive, .expired, .released:
            return false
        }
    }
    var isDraining: Bool { leaseState.isDraining }
    var isV2ControlVisible: Bool { authorityState != .legacyBroker || isDisablingAuthority }
    var hasLiveAgentSession: Bool { isAgentLive }
    var canAcquire: Bool {
        explicitAuthorityEnabled
            && !authorityReleasePending
            && !isWorking
            && !hasActiveLease
            && Self.canAcquire(status: statusProjection, agentIsLive: isAgentLive)
    }

    static func canAcquire(status: V2ClientStatusProjection?, agentIsLive: Bool) -> Bool {
        guard agentIsLive, let status else { return false }
        return status.processAlive
            && status.schedulerHealthy
            && status.serverConnected
            && !status.controlLeaseActive
            && !status.draining
            && !status.recoveryBlocked
            && !status.projectionLagging
    }

    static func effectiveAuthorityState(
        explicitAuthorityEnabled: Bool,
        leaseState: V2ClientControlLeaseState,
        releasePending: Bool
    ) -> V2ClientAuthorityState {
        if releasePending {
            return .v2Authority
        }
        switch leaseState {
        case .active, .draining:
            return .v2Authority
        case .inactive, .expired, .released:
            return explicitAuthorityEnabled ? .v2ReadOnly : .legacyBroker
        }
    }

    func setExplicitAuthorityEnabled(_ enabled: Bool) {
        explicitAuthorityEnabled = enabled
        defaults.set(enabled, forKey: V2ClientFeature.explicitAuthorityEnabledKey)
        configure()
        guard !enabled else {
            isDisablingAuthority = false
            authorityReleasePending = false
            defaults.set(false, forKey: V2ClientFeature.authorityReleasePendingKey)
            return
        }

        guard hasLeaseToRelease else {
            guard !authorityReleasePending else {
                isDisablingAuthority = true
                return
            }
            releaseAuthorityLocally()
            return
        }

        authorityReleasePending = true
        isDisablingAuthority = true
        defaults.set(true, forKey: V2ClientFeature.authorityReleasePendingKey)
        Task { [weak self] in
            await self?.drainForAuthorityDisable()
        }
    }

    func startLifecycle() {
        configure()
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshStatusNow()
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    return
                }
            }
        }
    }

    func stopLifecycle() {
        guard hasLeaseToRelease else {
            statusTask?.cancel()
            statusTask = nil
            return
        }
        authorityReleasePending = true
        isDisablingAuthority = true
        defaults.set(true, forKey: V2ClientFeature.authorityReleasePendingKey)
        Task { [weak self] in
            await self?.drainForAuthorityDisable()
        }
    }

    func refreshStatus() {
        Task { [weak self] in await self?.refreshStatusNow() }
    }
}
