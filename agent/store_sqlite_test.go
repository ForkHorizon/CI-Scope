package agent

import (
	"context"
	"path/filepath"
	"testing"
)

func TestSQLiteStoreUsesWALAndPersistsIntents(t *testing.T) {
	store, err := OpenSQLiteStore(filepath.Join(t.TempDir(), "agent.sqlite"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	ctx := context.Background()
	if err := store.PutMetadata(ctx, "machineId", "machine-1"); err != nil {
		t.Fatal(err)
	}
	if got, err := store.GetMetadata(ctx, "machineId"); err != nil || got != "machine-1" {
		t.Fatalf("metadata=%q err=%v", got, err)
	}
	intent := Intent{ID: "intent-1", OperationID: "op-1", Kind: IntentSpawnProcess, Status: IntentPending, LocalEpoch: 3, Payload: map[string]string{"runnerInstanceId": "runner-1"}}
	if err := store.PutIntent(ctx, intent); err != nil {
		t.Fatal(err)
	}
	pending, err := store.PendingIntents(ctx)
	if err != nil || len(pending) != 1 || pending[0].ID != intent.ID {
		t.Fatalf("pending=%+v err=%v", pending, err)
	}
	intent.Status = IntentAcknowledged
	if err := store.PutIntent(ctx, intent); err != nil {
		t.Fatal(err)
	}
	pending, err = store.PendingIntents(ctx)
	if err != nil || len(pending) != 0 {
		t.Fatalf("acknowledged intent remained: %+v err=%v", pending, err)
	}
}
