//go:build linux

package agent

import (
	"os"
	"syscall"
)

func socketOwnerUIDFromInfo(info os.FileInfo) (uint32, error) {
	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok {
		return 0, syscall.EINVAL
	}
	return stat.Uid, nil
}
