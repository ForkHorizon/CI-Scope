//go:build !darwin && !linux

package agent

import "errors"

func processStartTime(pid int) (int64, error) {
	return 0, errors.New("process start time is unsupported on this platform")
}
