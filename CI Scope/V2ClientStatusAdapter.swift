import Combine
import Foundation

enum V2ClientStatusResult: Equatable {
    case available(V2ClientStatusProjection)
    case unavailable(String)
}

/// Non-secret Agent discovery metadata written atomically by the Go Agent.
/// The socket still authenticates and fences every request; this file only
/// removes the need to copy live session values into UserDefaults manually.
