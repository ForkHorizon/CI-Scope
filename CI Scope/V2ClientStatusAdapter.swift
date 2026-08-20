import Combine
import Foundation

enum V2ClientStatusResult: Equatable {
  case available(V2ClientStatusProjection)
  case unavailable(String)

  var projection: V2ClientStatusProjection? {
    if case .available(let projection) = self { return projection }
    return nil
  }

  var error: String? {
    if case .unavailable(let message) = self { return message }
    return nil
  }
}

/// Non-secret Agent discovery metadata written atomically by the Go Agent.
/// The socket still authenticates and fences every request; this file only
/// removes the need to copy live session values into UserDefaults manually.
