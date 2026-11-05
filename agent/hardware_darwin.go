//go:build darwin

package agent

import (
	"context"
	"os/exec"
	"runtime"
	"time"

	"golang.org/x/sys/unix"
)

func probeHardware() HardwareFacts {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	facts := HardwareFacts{}
	if data, err := exec.CommandContext(ctx, "/usr/sbin/system_profiler", "-json", "SPHardwareDataType").Output(); err == nil {
		facts = parseSystemProfiler(data)
	}
	if facts.ModelID == "" {
		facts.ModelID, _ = unix.Sysctl("hw.model")
	}
	if facts.Chip == "" {
		facts.Chip, _ = unix.Sysctl("machdep.cpu.brand_string")
	}
	facts.MemoryBytes, _ = unix.SysctlUint64("hw.memsize")
	version, _ := unix.Sysctl("kern.osproductversion")
	facts.OS = macOSName(version)
	facts.CPUCores = runtime.NumCPU()
	facts.Arch = runtime.GOARCH
	return facts
}
