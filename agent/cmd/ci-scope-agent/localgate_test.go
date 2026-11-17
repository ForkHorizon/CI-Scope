// Tests that the local gate worker stays off without complete settings.
package main

import (
	"context"
	"testing"
)

func TestLocalGateWorkerStaysOffWithoutSettings(t *testing.T) {
	for _, name := range []string{envGatesRoot, envGatesSHA, envGateWorkspace} {
		t.Setenv(name, "")
	}
	stop, err := startLocalGateWorker(context.Background(), nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	stop()
}

func TestLocalGateWorkerNeedsAllSettingsTogether(t *testing.T) {
	t.Setenv(envGatesRoot, "/gates")
	t.Setenv(envGatesSHA, "")
	t.Setenv(envGateWorkspace, "")
	if _, err := startLocalGateWorker(context.Background(), nil); err == nil {
		t.Fatal("expected an error when only some settings are present")
	}
}

func TestGateParallelDefaultsToOneAndRejectsNonsense(t *testing.T) {
	for value, want := range map[string]int{"": 1, "1": 1, "3": 3, "8": 8} {
		if got, err := gateParallel(value); err != nil || got != want {
			t.Errorf("%q: got %d, %v; want %d", value, got, err, want)
		}
	}
	for _, value := range []string{"0", "-1", "9", "two"} {
		if _, err := gateParallel(value); err == nil {
			t.Errorf("%q: expected an error", value)
		}
	}
}
