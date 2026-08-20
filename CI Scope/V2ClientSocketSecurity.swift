import Darwin
import Foundation

nonisolated enum V2ClientUnixSocketSecurity {
    static func validate(
        socketURL: URL,
        expectedOwnerUID: UInt32 = UInt32(geteuid()),
        requiredMode: UInt16 = 0o600
    ) throws {
        var info = stat()
        guard lstat(socketURL.path, &info) == 0 else { throw V2ClientBridgeError.socketNotFound }
        guard (info.st_mode & S_IFMT) == S_IFSOCK else { throw V2ClientBridgeError.notUnixSocket }
        let mode = UInt16(info.st_mode & 0o777)
        guard mode == requiredMode else { throw V2ClientBridgeError.insecureSocketMode(mode) }
        let owner = UInt32(info.st_uid)
        guard owner == expectedOwnerUID else { throw V2ClientBridgeError.unexpectedSocketOwner(owner) }
    }
}
