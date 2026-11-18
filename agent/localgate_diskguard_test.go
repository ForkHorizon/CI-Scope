// Tests for the disk guard that stops a gate command writing without bound.
package agent

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestDiskGuardKillsACommandThatFloodsItsCheckout(t *testing.T) {
	maxWorkspaceBytes, diskGuardInterval = 1<<20, 50*time.Millisecond
	t.Cleanup(func() { maxWorkspaceBytes, diskGuardInterval = 8<<30, 5*time.Second })
	dir := t.TempDir()
	started := time.Now()
	_, err := execCommand(context.Background(), dir, "sh", "-c", "head -c 3000000 /dev/zero > flood.log; sleep 30")
	var stopped *environmentError
	if !errors.As(err, &stopped) {
		t.Fatalf("want an environment error, got %v", err)
	}
	if time.Since(started) > 10*time.Second {
		t.Fatalf("the flood was not stopped promptly: %v", time.Since(started))
	}
}

func TestDiskGuardLeavesAQuietCommandAlone(t *testing.T) {
	out, err := execCommand(context.Background(), t.TempDir(), "sh", "-c", "echo fine")
	if err != nil || string(out) != "fine\n" {
		t.Fatalf("got %q, %v", out, err)
	}
}
