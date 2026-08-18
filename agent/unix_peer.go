package agent

import (
	"errors"
	"net"
)

var errPeerCredentialsUnavailable = errors.New("unix peer credentials are unavailable")

func unixPeerUID(conn *net.UnixConn) (uint32, error) {
	if conn == nil {
		return 0, errPeerCredentialsUnavailable
	}
	raw, err := conn.SyscallConn()
	if err != nil {
		return 0, err
	}
	var uid uint32
	var controlErr error
	if err := raw.Control(func(fd uintptr) {
		uid, controlErr = peerUIDFromFD(int(fd))
	}); err != nil {
		return 0, err
	}
	if controlErr != nil {
		return 0, controlErr
	}
	return uid, nil
}
