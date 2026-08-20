import Combine
import Darwin
import Foundation

@MainActor
final class RunnerFleetViewModel: ObservableObject {
  @Published private(set) var snapshot = RunnerFleetSnapshot()
  @Published private(set) var isLoading = false

  private let service: RunnerFleetService
  private var agentMonitor: V2AgentStateMonitor?
  private var isApplyingLiveUpdate = false
  private var lastAppliedSignature: String?
  private var pendingSignature: String?
  private var loadGeneration = 0

  init() {
    let config = DashboardConfig()
    self.service = RunnerFleetService(config: config)
  }

  func load(projects: [CIProject]? = nil) async {
    isLoading = true
    let generation = loadGeneration + 1
    loadGeneration = generation
    let signatureAtStart = lastAppliedSignature

    let nextSnapshot = await service.loadSnapshot(projects: projects)
    guard loadGeneration == generation else { return }

    if lastAppliedSignature == signatureAtStart {
      snapshot = nextSnapshot
      NotificationManager.shared.checkWorkUpdates(snapshot: nextSnapshot)
      NotificationManager.shared.checkRunnerUpdates(runners: nextSnapshot.runners)
    }

    isLoading = false
  }

  func startLiveUpdates(onRunnerChange: @escaping @MainActor () async -> Void) {
    guard agentMonitor == nil else { return }
    let monitor = V2AgentStateMonitor { [weak self] signature in
      Task { @MainActor [weak self] in
        await self?.applyLiveUpdate(signature: signature, onRunnerChange: onRunnerChange)
      }
    }
    agentMonitor = monitor
    monitor.start()
  }

  func stopLiveUpdates() {
    agentMonitor?.stop()
    agentMonitor = nil
    pendingSignature = nil
    isApplyingLiveUpdate = false
  }

  private func applyLiveUpdate(
    signature: String,
    onRunnerChange: @escaping @MainActor () async -> Void
  ) async {
    guard signature != lastAppliedSignature else { return }
    pendingSignature = signature
    guard !isApplyingLiveUpdate else { return }

    isApplyingLiveUpdate = true
    while let nextSignature = pendingSignature {
      pendingSignature = nil
      guard nextSignature != lastAppliedSignature else { continue }

      let nextSnapshot = await service.loadSnapshot()
      snapshot = nextSnapshot
      lastAppliedSignature = nextSignature
      NotificationManager.shared.checkWorkUpdates(snapshot: nextSnapshot)
      NotificationManager.shared.checkRunnerUpdates(runners: nextSnapshot.runners)
      await onRunnerChange()
    }
    isApplyingLiveUpdate = false
  }
}

private final class V2AgentStateMonitor {
  private let queue = DispatchQueue(label: "ci-scope.v2-agent-state-monitor")
  private let fileManager = FileManager.default
  private let onChange: (String) -> Void

  private var sources: [DispatchSourceFileSystemObject] = []
  private var pollTimer: DispatchSourceTimer?
  private var debounceWorkItem: DispatchWorkItem?
  private var lastSignature: String?
  private var isRunning = false

  init(onChange: @escaping (String) -> Void) {
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
    let descriptorURL = V2ClientAgentSessionDescriptor.url
    watch(path: descriptorURL.deletingLastPathComponent().path)
    watch(path: descriptorURL.path)
  }

  private func cancelWatchesLocked() {
    for source in sources {
      source.cancel()
    }
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
    let descriptor = V2ClientAgentSessionDescriptor.load()
    let descriptorPart =
      descriptor.map {
        "\($0.sessionID):\($0.sessionEpoch):\($0.localOwnerEpoch):\($0.fencingToken)"
      } ?? "no-descriptor"

    let defaults = UserDefaults.standard
    let authorityState = V2ClientFeature.authorityState(defaults: defaults).rawValue
    let adapterPart =
      "\(V2ClientFeature.statusAdapterEnabled(defaults: defaults)):\(authorityState)"

    return "\(descriptorPart)|\(adapterPart)"
  }
}
