//go:build !darwin && !linux

package agent

import "errors"

func peerUIDFromFD(_ int) (uint32, error) {
	return 0, errors.New("unix peer credentials are unsupported on this platform")
}
