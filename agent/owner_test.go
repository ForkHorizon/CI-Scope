package agent

import (
	"path/filepath"
	"testing"
)

func TestOwnerLeaseFencesContentionAndRelease(t *testing.T) {
	root := filepath.Join(t.TempDir(), "state")
	one, err := AcquireOwnerLock(root, "agent-one")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := AcquireOwnerLock(root, "agent-two"); err == nil {
		t.Fatal("second agent acquired owner lock")
	}
	token := one.Token()
	if err := one.Check(token); err != nil {
		t.Fatal(err)
	}
	if err := one.Release(); err != nil {
		t.Fatal(err)
	}
	if err := one.Check(token); err == nil {
		t.Fatal("released owner accepted fencing token")
	}
	two, err := AcquireOwnerLock(root, "agent-two")
	if err != nil {
		t.Fatal(err)
	}
	defer two.Release()
	if two.Token().LocalEpoch <= token.LocalEpoch {
		t.Fatalf("epoch did not advance: old=%d new=%d", token.LocalEpoch, two.Token().LocalEpoch)
	}
}
