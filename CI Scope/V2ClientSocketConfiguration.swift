import Darwin
import Foundation

nonisolated struct V2ClientUnixSocketConfiguration: Sendable {
    let socketURL: URL
    let expectedPeerUID: UInt32
    let requiredMode: UInt16
    let maximumFrameBytes: Int
    let ioTimeout: TimeInterval

    init(
        socketURL: URL,
        expectedPeerUID: UInt32 = UInt32(geteuid()),
        maximumFrameBytes: Int = 1_048_576,
        ioTimeout: TimeInterval = 1
    ) {
        self.socketURL = socketURL
        self.expectedPeerUID = expectedPeerUID
        self.requiredMode = 0o600
        self.maximumFrameBytes = maximumFrameBytes
        self.ioTimeout = ioTimeout
    }
}
