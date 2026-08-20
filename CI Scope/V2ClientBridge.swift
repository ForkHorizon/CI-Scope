import Foundation

enum V2ClientBridgeError: Error, Equatable, CustomStringConvertible {
  case unsupportedProtocolVersion(Int)
  case invalidFencingContext
  case invalidResponseContext
  case invalidServerRevision
  case invalidPayloadHash(expected: String, actual: String)
  case invalidResponseRequestID
  case insecureSocketMode(UInt16)
  case notUnixSocket
  case unexpectedSocketOwner(UInt32)
  case socketNotFound
  case socketFailure(String)
  case frameTooLarge
  case malformedFrame
  case invalidLeaseTransition
  case authorityRequired
  case controlLeaseRequired
  case invalidControlCommand

  var description: String {
    switch self {
    case .unsupportedProtocolVersion(let version):
      return "Unsupported protocol version \(version)"
    case .invalidFencingContext:
      return "Fencing context does not match the session"
    case .invalidResponseContext:
      return "Response context does not match the request"
    case .invalidServerRevision:
      return "Server revision must be non-negative"
    case .invalidPayloadHash(let expected, let actual):
      return "Payload hash mismatch (expected \(expected), got \(actual))"
    case .invalidResponseRequestID:
      return "Response requestId does not match the request"
    case .insecureSocketMode(let mode):
      return String(format: "Unix socket must be mode 0600, got %04o", mode)
    case .notUnixSocket:
      return "Endpoint is not a Unix-domain socket"
    case .unexpectedSocketOwner(let uid):
      return "Unix socket owner UID \(uid) is not trusted"
    case .socketNotFound:
      return "Unix socket does not exist"
    case .socketFailure(let message):
      return message
    case .frameTooLarge:
      return "Unix socket frame is too large"
    case .malformedFrame:
      return "Unix socket frame is malformed"
    case .invalidLeaseTransition:
      return "Invalid control lease transition"
    case .authorityRequired:
      return "V2 authority is not enabled"
    case .controlLeaseRequired:
      return "An active V2 control lease is required"
    case .invalidControlCommand:
      return "Command is not valid for the selected control path"
    }
  }
}
