//go:build !darwin && !linux

package agent

import (
	"errors"
	"os"
)

func socketOwnerUIDFromInfo(_ os.FileInfo) (uint32, error) {
	return 0, errors.New("unix socket ownership is unsupported on this platform")
}
