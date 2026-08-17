import Foundation
import Darwin

public struct V2ClientPeerCredentials: Equatable {
    public let uid: UInt32
    public let gid: UInt32

    public init(uid: UInt32, gid: UInt32) {
        self.uid = uid
        self.gid = gid
    }
}

public struct V2ClientUnixSocketConfiguration {
    public let socketURL: URL
    public let expectedPeerUID: UInt32
    public let requiredMode: UInt16
    public let maximumFrameBytes: Int
    public let ioTimeout: TimeInterval

    public init(
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

