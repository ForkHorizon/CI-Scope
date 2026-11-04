// Detects which build tools this device has, so the server only sends it jobs it can run.
package main

import (
	"os"
	"strings"

	"github.com/forkhorizon/ci-scope/agent"
)

const envCapabilities = "CI_SCOPE_CAPABILITIES"

// toolForCapability maps a capability name to the executable that proves it.
var toolForCapability = map[string]string{
	"xcode":  "xcodebuild",
	"cargo":  "cargo",
	"go":     "go",
	"node":   "node",
	"python": "python3",
	"unity":  "Unity",
}

// detectCapabilities returns the explicit list from CI_SCOPE_CAPABILITIES when set, otherwise the tools found on PATH.
func detectCapabilities(lookPath func(string) (string, error)) []string {
	if explicit, ok := os.LookupEnv(envCapabilities); ok {
		return splitCapabilities(explicit)
	}
	found := []string{}
	for _, name := range []string{"cargo", "go", "node", "python", "unity", "xcode"} {
		if _, err := lookPath(toolForCapability[name]); err == nil {
			found = append(found, name)
		}
	}
	return found
}

func splitCapabilities(value string) []string {
	items := []string{}
	for _, part := range strings.Split(value, ",") {
		if name := strings.TrimSpace(part); name != "" {
			items = append(items, name)
		}
	}
	return items
}

func lookPathOnSystem(name string) (string, error) { return agent.LookGatePath(name) }
