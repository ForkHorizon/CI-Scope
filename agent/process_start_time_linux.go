//go:build linux

package agent

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

func processStartTime(pid int) (int64, error) {
	data, err := os.ReadFile(fmt.Sprintf("/proc/%d/stat", pid))
	if err != nil {
		return 0, err
	}
	line := string(data)
	closeComm := strings.LastIndexByte(line, ')')
	if closeComm < 0 || closeComm+2 > len(line) {
		return 0, fmt.Errorf("invalid process stat for pid %d", pid)
	}
	fields := strings.Fields(line[closeComm+2:])
	if len(fields) < 20 {
		return 0, fmt.Errorf("incomplete process stat for pid %d", pid)
	}
	value, err := strconv.ParseInt(fields[19], 10, 64)
	if err != nil {
		return 0, fmt.Errorf("parse process start time: %w", err)
	}
	return value, nil
}
