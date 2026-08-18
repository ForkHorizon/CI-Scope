package agent

import (
	"path/filepath"
	"testing"
	"time"
)

func TestIntentJournalReturnsUnacknowledgedIntents(t *testing.T) {
	j, err := OpenIntentJournal(filepath.Join(t.TempDir(), "intents.jsonl"))
	if err != nil {
		t.Fatal(err)
	}
	defer j.Close()
	intent := Intent{ID: "intent-1", OperationID: "op-1", Kind: IntentSpawnProcess, Status: IntentPending, LocalEpoch: 3, CreatedAt: time.Now().UTC()}
	if err := j.Append(intent); err != nil {
		t.Fatal(err)
	}
	pending, err := j.Pending()
	if err != nil || len(pending) != 1 || pending[0].ID != intent.ID {
		t.Fatalf("pending=%+v err=%v", pending, err)
	}
	intent.Status = IntentAcknowledged
	if err := j.Append(intent); err != nil {
		t.Fatal(err)
	}
	pending, err = j.Pending()
	if err != nil || len(pending) != 0 {
		t.Fatalf("acknowledged intent remained pending: %+v err=%v", pending, err)
	}
}
