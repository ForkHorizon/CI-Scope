import Foundation
import os

/// Structured JSON-lines logging for the GUI app, mirroring the broker's
/// broker.jsonl/broker-errors.jsonl format so both halves of the system read
/// the same way during a stress test. Also mirrors every line to os.Logger
/// (Console.app / `log stream`) since that's free and some people prefer it.
///
/// Hard crashes (force-unwrap, trap) aren't catchable in-process — macOS's own
/// crash reporter already captures those reliably into
/// ~/Library/Logs/DiagnosticReports/CI Scope-*.ips, so this doesn't attempt a
/// custom signal handler. It does catch uncaught NSExceptions, the one crash
/// class Cocoa lets you intercept.
enum LogLevel: String {
  case debug = "DEBUG"
  case info = "INFO"
  case warn = "WARN"
  case error = "ERROR"
  case crash = "CRASH"

  var osType: OSLogType {
    switch self {
    case .debug: return .debug
    case .info: return .info
    case .warn: return .default
    case .error: return .error
    case .crash: return .fault
    }
  }
}

final class AppLogger {
  static let shared = AppLogger()

  private let mainURL: URL
  private let errorURL: URL
  private let queue = DispatchQueue(label: "com.ci-scope.app-logger")
  private let osLogger = Logger(subsystem: "com.ForkHorizon.CI-Scope", category: "app")
  private let maxBytes: UInt64 = 20 * 1024 * 1024
  private let maxBackups = 5
  private let isoFormatter = ISO8601DateFormatter()

  private init() {
    let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Logs/CI Scope/App", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    mainURL = dir.appendingPathComponent("app.jsonl")
    errorURL = dir.appendingPathComponent("app-errors.jsonl")
  }

  func debug(_ event: String, _ message: String, context: [String: Any] = [:]) {
    log(.debug, event: event, message, context: context)
  }

  func info(_ event: String, _ message: String, context: [String: Any] = [:]) {
    log(.info, event: event, message, context: context)
  }

  func warn(_ event: String, _ message: String, context: [String: Any] = [:]) {
    log(.warn, event: event, message, context: context)
  }

  /// Synchronous by design: called from the uncaught-exception handler,
  /// which may have only moments before the process dies.
  func crash(_ event: String, _ message: String, context: [String: Any] = [:]) {
    log(.crash, event: event, message, context: context, synchronous: true)
  }

  private func log(
    _ level: LogLevel, event: String, _ message: String, context: [String: Any],
    synchronous: Bool = false
  ) {
    osLogger.log(level: level.osType, "\(event, privacy: .public): \(message, privacy: .public)")

    let work = { [self] in
      var payload: [String: Any] = [
        "ts": isoFormatter.string(from: Date()),
        "level": level.rawValue,
        "component": "app",
        "event": event,
        "msg": message,
      ]
      if !context.isEmpty { payload["context"] = context }
      guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
        var line = String(data: data, encoding: .utf8)
      else { return }
      line += "\n"
      append(line, to: mainURL)
      if level == .warn || level == .error || level == .crash {
        append(line, to: errorURL)
      }
    }
    if synchronous {
      queue.sync(execute: work)
    } else {
      queue.async(execute: work)
    }
  }

  private func append(_ line: String, to url: URL) {
    rotateIfNeeded(url)
    guard let data = line.data(using: .utf8) else { return }
    let fm = FileManager.default
    if !fm.fileExists(atPath: url.path) {
      fm.createFile(atPath: url.path, contents: nil)
    }
    guard let handle = try? FileHandle(forWritingTo: url) else { return }
    defer { try? handle.close() }
    handle.seekToEndOfFile()
    handle.write(data)
  }

  private func rotateIfNeeded(_ url: URL) {
    let fm = FileManager.default
    guard let size = try? fm.attributesOfItem(atPath: url.path)[.size] as? UInt64, size > maxBytes
    else { return }
    let base = url.deletingPathExtension().path
    let ext = url.pathExtension
    try? fm.removeItem(atPath: "\(base).\(maxBackups).\(ext)")
    for index in stride(from: maxBackups - 1, through: 1, by: -1) {
      let src = "\(base).\(index).\(ext)"
      let dst = "\(base).\(index + 1).\(ext)"
      if fm.fileExists(atPath: src) {
        try? fm.moveItem(atPath: src, toPath: dst)
      }
    }
    try? fm.moveItem(atPath: url.path, toPath: "\(base).1.\(ext)")
  }
}
