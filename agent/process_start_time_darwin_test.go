//go:build darwin

package agent

import (
	"os"
	"testing"
)

func TestProcessStartTimeReadsCurrentProcess(t *testing.T) {
	startTime, err := processStartTime(os.Getpid())
	if err != nil {
		t.Fatal(err)
	}
	if startTime <= 0 {
		t.Fatalf("start time = %d, want positive value", startTime)
	}
}
