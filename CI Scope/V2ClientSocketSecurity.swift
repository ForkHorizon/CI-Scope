import Foundation
import Darwin

public enum V2ClientUnixSocketSecurity {
    public static func validate(
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

    public static func enforce0600(socketURL: URL) throws {
        guard chmod(socketURL.path, mode_t(0o600)) == 0 else {
            throw V2ClientBridgeError.socketFailure("Could not set Unix socket mode 0600")
        }
        try validate(socketURL: socketURL)
    }
}

