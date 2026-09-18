//go:build darwin

package agent

import (
	"golang.org/x/sys/unix"
)

func processStartTime(pid int) (int64, error) {
	info, err := unix.SysctlKinfoProc("kern.proc.pid", pid)
	if err != nil {
		return 0, err
	}
	return int64(info.Proc.P_starttime.Sec)*1_000_000_000 + int64(info.Proc.P_starttime.Usec)*1_000, nil
}
