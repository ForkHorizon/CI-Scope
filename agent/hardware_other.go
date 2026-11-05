//go:build !darwin

package agent

import "runtime"

func probeHardware() HardwareFacts {
	return HardwareFacts{OS: runtime.GOOS, Arch: runtime.GOARCH, CPUCores: runtime.NumCPU()}
}
