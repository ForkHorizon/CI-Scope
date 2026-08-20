import Darwin
import Foundation

final class V2ClientUnixSocketTransport: @unchecked Sendable {
  typealias PeerUIDValidationHook = (UInt32) -> Bool

  private let configuration: V2ClientUnixSocketConfiguration
  private let peerUIDValidationHook: PeerUIDValidationHook

  init(
    configuration: V2ClientUnixSocketConfiguration,
    peerUIDValidationHook: PeerUIDValidationHook? = nil
  ) {
    self.configuration = configuration
    self.peerUIDValidationHook =
      peerUIDValidationHook ?? { uid in
        uid == configuration.expectedPeerUID
      }
  }

  nonisolated func send<RequestPayload: Codable & Sendable, ResponsePayload: Codable & Sendable>(
    _ request: V2ClientRequestEnvelope<RequestPayload>,
    responseType: ResponsePayload.Type
  ) throws -> V2ClientResponseEnvelope<ResponsePayload> {
    try request.validate()
    try V2ClientUnixSocketSecurity.validate(
      socketURL: configuration.socketURL,
      expectedOwnerUID: configuration.expectedPeerUID,
      requiredMode: configuration.requiredMode
    )

    let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else {
      throw V2ClientBridgeError.socketFailure("Could not create Unix socket")
    }
    defer { close(descriptor) }
    try configureTimeouts(descriptor)
    try connect(descriptor)
    try validatePeer(descriptor)

    let requestFrame = try V2ClientWireCodec.encodeFrame(
      request, maximumBytes: configuration.maximumFrameBytes)
    try writeAll(requestFrame, to: descriptor)
    let responseFrame = try readFrame(from: descriptor)
    let response = try V2ClientWireCodec.decodeFrame(
      responseFrame,
      as: V2ClientResponseEnvelope<ResponsePayload>.self,
      maximumBytes: configuration.maximumFrameBytes
    )
    guard response.requestId == request.requestId else {
      throw V2ClientBridgeError.invalidResponseRequestID
    }
    try response.validateAgainst(request: request)
    return response
  }

  private func configureTimeouts(_ descriptor: Int32) throws {
    var noSigPipe: Int32 = 1
    guard
      setsockopt(
        descriptor,
        SOL_SOCKET,
        SO_NOSIGPIPE,
        &noSigPipe,
        socklen_t(MemoryLayout<Int32>.size)
      ) == 0
    else {
      throw V2ClientBridgeError.socketFailure("Could not configure Unix socket")
    }

    var timeout = timeval(
      tv_sec: Int(configuration.ioTimeout),
      tv_usec: Int32((configuration.ioTimeout.truncatingRemainder(dividingBy: 1)) * 1_000_000)
    )
    guard
      setsockopt(
        descriptor,
        SOL_SOCKET,
        SO_RCVTIMEO,
        &timeout,
        socklen_t(MemoryLayout<timeval>.size)
      ) == 0,
      setsockopt(
        descriptor,
        SOL_SOCKET,
        SO_SNDTIMEO,
        &timeout,
        socklen_t(MemoryLayout<timeval>.size)
      ) == 0
    else {
      throw V2ClientBridgeError.socketFailure("Could not configure Unix socket timeout")
    }
  }

  private func connect(_ descriptor: Int32) throws {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(configuration.socketURL.path.utf8) + [0]
    let pathOffset = MemoryLayout<sockaddr_un>.offset(of: \sockaddr_un.sun_path)!
    guard pathOffset + pathBytes.count <= MemoryLayout<sockaddr_un>.size else {
      throw V2ClientBridgeError.socketFailure("Unix socket path is too long")
    }
    withUnsafeMutableBytes(of: &address) { rawBuffer in
      rawBuffer.baseAddress!.advanced(by: pathOffset).copyMemory(
        from: pathBytes,
        byteCount: pathBytes.count
      )
    }
    let addressLength = socklen_t(pathOffset + pathBytes.count)
    let result = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(descriptor, $0, addressLength)
      }
    }
    guard result == 0 else {
      throw V2ClientBridgeError.socketFailure("Could not connect to Agent Unix socket")
    }
  }

  private func validatePeer(_ descriptor: Int32) throws {
    var uid: uid_t = 0
    var gid: gid_t = 0
    guard getpeereid(descriptor, &uid, &gid) == 0 else {
      throw V2ClientBridgeError.socketFailure("Could not validate Agent peer UID")
    }
    guard peerUIDValidationHook(UInt32(uid)) else {
      throw V2ClientBridgeError.unexpectedSocketOwner(UInt32(uid))
    }
  }

  private func writeAll(_ data: Data, to descriptor: Int32) throws {
    var written = 0
    try data.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) in
      guard let baseAddress = rawBuffer.baseAddress else { return }
      while written < data.count {
        let result = Darwin.send(
          descriptor,
          baseAddress.advanced(by: written),
          data.count - written,
          0
        )
        guard result > 0 else {
          throw V2ClientBridgeError.socketFailure("Could not write Agent request")
        }
        written += result
      }
    }
  }

  private func readFrame(from descriptor: Int32) throws -> Data {
    var frame = Data()
    var byte: UInt8 = 0
    while frame.count < configuration.maximumFrameBytes {
      let result = withUnsafeMutableBytes(of: &byte) { rawBuffer in
        Darwin.recv(descriptor, rawBuffer.baseAddress!, 1, 0)
      }
      guard result > 0 else {
        throw V2ClientBridgeError.socketFailure("Could not read Agent response")
      }
      frame.append(byte)
      if byte == 0x0A { return frame }
    }
    throw V2ClientBridgeError.frameTooLarge
  }
}
