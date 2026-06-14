import Foundation
import Combine
import Darwin

@MainActor
final class RunnerFleetViewModel: ObservableObject {
    @Published private(set) var snapshot = RunnerFleetSnapshot()
    @Published private(set) var isLoading = false

    private let service: RunnerFleetService
    private let brokerService: LocalBrokerService
    private var brokerMonitor: BrokerStateMonitor?
    private var isApplyingLiveUpdate = false
    private var lastAppliedBrokerSignature: String?
    private var pendingBrokerSignature: String?
    private var loadGeneration = 0

    init() {
        let config = DashboardConfig()
        self.service = RunnerFleetService(config: config)
        self.brokerService = LocalBrokerService(config: config)
    }

    func load() async {
        isLoading = true
        let generation = loadGeneration + 1
        loadGeneration = generation
        let brokerSignatureAtStart = lastAppliedBrokerSignature

        let nextSnapshot = await service.loadSnapshot()
        guard loadGeneration == generation else { return }

        // A live broker update applied fresher data while we were loading; don't
        // clobber it with the snapshot captured before that update (it already
        // fired its own notifications).
        if lastAppliedBrokerSignature == brokerSignatureAtStart {
            snapshot = nextSnapshot
            NotificationManager.shared.checkWorkUpdates(snapshot: nextSnapshot)
            NotificationManager.shared.checkRunnerUpdates(runners: nextSnapshot.runners)
        }

        isLoading = false
    }

    func startLiveUpdates(onBrokerChange: @escaping @MainActor () async -> Void) {
        guard brokerMonitor == nil else { return }
        let monitor = BrokerStateMonitor(service: brokerService) { [weak self] signature in
            Task { @MainActor [weak self] in
                await self?.applyLiveUpdate(signature: signature, onBrokerChange: onBrokerChange)
            }
        }
        brokerMonitor = monitor
        monitor.start()
    }

    func stopLiveUpdates() {
        brokerMonitor?.stop()
        brokerMonitor = nil
        pendingBrokerSignature = nil
        isApplyingLiveUpdate = false
    }

    private func applyLiveUpdate(
        signature: String,
        onBrokerChange: @escaping @MainActor () async -> Void
    ) async {
        guard signature != lastAppliedBrokerSignature else { return }
        pendingBrokerSignature = signature
        guard !isApplyingLiveUpdate else { return }

        isApplyingLiveUpdate = true
        while let nextSignature = pendingBrokerSignature {
            pendingBrokerSignature = nil
            guard nextSignature != lastAppliedBrokerSignature else { continue }

            let nextSnapshot = await service.loadSnapshot(prepareBroker: false)
            snapshot = nextSnapshot
            lastAppliedBrokerSignature = nextSignature
            NotificationManager.shared.checkWorkUpdates(snapshot: nextSnapshot)
            NotificationManager.shared.checkRunnerUpdates(runners: nextSnapshot.runners)
            await onBrokerChange()
        }
        isApplyingLiveUpdate = false
    }
}

private final class BrokerStateMonitor {
    private let service: LocalBrokerService
    private let queue = DispatchQueue(label: "ci-scope.broker-state-monitor")
    private let fileManager = FileManager.default
    private let onChange: (String) -> Void

    private var sources: [DispatchSourceFileSystemObject] = []
    private var pollTimer: DispatchSourceTimer?
    private var debounceWorkItem: DispatchWorkItem?
    private var lastSignature: String?
    private var isRunning = false

    init(service: LocalBrokerService, onChange: @escaping (String) -> Void) {
        self.service = service
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !self.isRunning else { return }
            self.isRunning = true
            self.armWatchesLocked()
            self.startFallbackPollLocked()
            self.emitIfChangedLocked()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isRunning = false
            self.debounceWorkItem?.cancel()
            self.debounceWorkItem = nil
            self.cancelWatchesLocked()
            self.pollTimer?.cancel()
            self.pollTimer = nil
        }
    }

    private func armWatchesLocked() {
        cancelWatchesLocked()
        watch(path: service.brokerDirectory.path)
        watch(path: service.stateURL.path)
        watch(path: service.registryURL.path)
    }

    private func cancelWatchesLocked() {
        sources.forEach { $0.cancel() }
        sources.removeAll()
    }

    private func watch(path: String) {
        guard fileManager.fileExists(atPath: path) else { return }
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend, .attrib],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.scheduleDebouncedCheckLocked(rearmWatches: true)
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        sources.append(source)
    }

    private func startFallbackPollLocked() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            self?.emitIfChangedLocked()
        }
        timer.resume()
        pollTimer = timer
    }

    private func scheduleDebouncedCheckLocked(rearmWatches: Bool) {
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning else { return }
            if rearmWatches {
                self.armWatchesLocked()
            }
            self.emitIfChangedLocked()
        }
        debounceWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func emitIfChangedLocked() {
        guard isRunning else { return }
        let signature = currentSignature()
        guard signature != lastSignature else { return }
        lastSignature = signature
        onChange(signature)
    }

    private func currentSignature() -> String {
        let registry = service.loadRegistry()
        let state = service.loadState()
        let activeID = state.activeJobs.isEmpty ? "-" : state.activeJobs.map(\.id).sorted().joined(separator: ",")
        let queueIDs = state.queue.map(\.id).joined(separator: ",")
        let webhook =
            state.webhook.map { status in
                [
                    status.enabled.description,
                    status.port.map(String.init) ?? "-",
                    status.lastDeliveryAt ?? "-",
                    status.lastDeliveryID ?? "-",
                    status.lastAction ?? "-",
                    status.lastRepository ?? "-",
                    status.lastJob ?? "-",
                    status.lastError ?? "-",
                ].joined(separator: ":")
            } ?? "-"
        let repoStatuses = state.repos
            .map { "\($0.profileID ?? "-"):\($0.slug):\($0.state):\($0.queuedCount):\($0.lastError ?? "-")" }
            .joined(separator: ",")
        let profiles = registry.profiles
            .map { "\($0.id):\($0.enabled):\($0.labels.joined(separator: "+"))" }
            .joined(separator: ",")
        let repos = registry.repos
            .map { "\($0.slug):\($0.enabled):\($0.labels.joined(separator: "+"))" }
            .joined(separator: ",")

        return [
            state.updatedAt,
            activeID,
            queueIDs,
            webhook,
            repoStatuses,
            profiles,
            repos,
        ].joined(separator: "|")
    }
}
