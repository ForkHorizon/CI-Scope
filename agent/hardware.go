package agent

import (
	"encoding/json"
	"strconv"
	"strings"
	"sync"
)

// HardwareFacts is what the server may show about this machine, sent once when a session opens.
// It deliberately has no serial number, hardware UUID, host name or user name.
type HardwareFacts struct {
	ModelName   string `json:"modelName,omitempty"`   // "MacBook Pro"
	ModelID     string `json:"modelId,omitempty"`     // "MacBookPro18,3"
	Chip        string `json:"chip,omitempty"`        // "Apple M1 Pro"
	MemoryBytes uint64 `json:"memoryBytes,omitempty"` // installed RAM
	CPUCores    int    `json:"cpuCores,omitempty"`    // logical cores
	OS          string `json:"os,omitempty"`          // "macOS 15.2"
	Arch        string `json:"arch,omitempty"`        // "arm64"
}

var (
	hardwareOnce  sync.Once
	hardwareCache HardwareFacts
)

// readHardware is a variable so tests can replace the probe; the real one runs once per process.
var readHardware = func() HardwareFacts {
	hardwareOnce.Do(func() { hardwareCache = probeHardware() })
	return hardwareCache
}

// parseSystemProfiler reads `system_profiler -json SPHardwareDataType` and keeps only the harmless fields.
func parseSystemProfiler(data []byte) HardwareFacts {
	var out struct {
		Items []struct {
			MachineName  string `json:"machine_name"`
			MachineModel string `json:"machine_model"`
			ChipType     string `json:"chip_type"`
			CPUType      string `json:"cpu_type"`
		} `json:"SPHardwareDataType"`
	}
	if err := json.Unmarshal(data, &out); err != nil || len(out.Items) == 0 {
		return HardwareFacts{}
	}
	item := out.Items[0]
	chip := item.ChipType
	if chip == "" {
		chip = item.CPUType
	}
	return HardwareFacts{ModelName: shortText(item.MachineName), ModelID: shortText(item.MachineModel), Chip: shortText(chip)}
}

// macOSName turns a product version ("15.2") into "macOS 15.2".
func macOSName(version string) string {
	version = strings.TrimSpace(version)
	if version == "" {
		return ""
	}
	if _, err := strconv.ParseFloat(strings.SplitN(version, ".", 2)[0], 64); err != nil {
		return ""
	}
	return "macOS " + version
}

// shortText keeps a reported string short and printable; the server applies the same limit.
func shortText(value string) string {
	value = strings.TrimSpace(value)
	if len(value) > 64 {
		value = value[:64]
	}
	return value
}
