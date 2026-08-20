import Foundation

extension URL {
  enum SafeAppendError: LocalizedError {
    case pathTraversal(String)

    var errorDescription: String? {
      switch self {
      case .pathTraversal(let path):
        return "Path traversal detected in component: \(path)"
      }
    }
  }

  /// Appends a path component while ensuring the resulting URL is a descendant of `self`.
  /// Throws an error if a path traversal attack is detected (e.g., using "../").
  func safelyAppendingPathComponent(_ pathComponent: String, isDirectory: Bool = false) throws
    -> URL
  {
    let component = pathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !component.isEmpty else {
      return self
    }

    // Prevent absolute paths from replacing the base URL entirely
    if component.hasPrefix("/") {
      throw SafeAppendError.pathTraversal(component)
    }

    let appended = self.appendingPathComponent(component, isDirectory: isDirectory)

    let basePath = self.standardized.resolvingSymlinksInPath().path
    let appendedPath = appended.standardized.resolvingSymlinksInPath().path
    let prefix = basePath.hasSuffix("/") ? basePath : basePath + "/"

    // Verify that the new path is strictly a subpath of the base path.
    if appendedPath != basePath && !appendedPath.hasPrefix(prefix) {
      throw SafeAppendError.pathTraversal(component)
    }

    return appended
  }
}
