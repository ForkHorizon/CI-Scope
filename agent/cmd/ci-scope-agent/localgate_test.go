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
