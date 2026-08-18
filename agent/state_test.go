package agent

import (
	"context"
	"testing"
)

func TestStateOwnerRejectsStaleResult(t *testing.T) {
	owner, err := NewStateOwner(StateRecovering, 2, 7)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go func() { _ = owner.Run(ctx) }()
	result := <-owner.Submit(ctx, TransitionRequest{OperationID: "stale", To: StateReady, LocalEpoch: 1, ServerSessionEpoch: 7})
	if !result.Stale || result.Applied {
		t.Fatalf("expected stale result: %+v", result)
	}
}

func TestStateOwnerSerializesOnlyValidTransitions(t *testing.T) {
	owner, err := NewStateOwner(StateRecovering, 2, 7)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go func() { _ = owner.Run(ctx) }()
	result := <-owner.Submit(ctx, TransitionRequest{OperationID: "ready", To: StateReady, ExpectedState: StateRecovering, LocalEpoch: 2, ServerSessionEpoch: 7})
	if !result.Applied || owner.Snapshot().State != StateReady {
		t.Fatalf("expected ready: %+v", result)
	}
	invalid := <-owner.Submit(ctx, TransitionRequest{OperationID: "bad", To: StateDormant, ExpectedState: StateReady, LocalEpoch: 2, ServerSessionEpoch: 7})
	if invalid.Err == nil || invalid.Applied {
		t.Fatalf("expected invalid transition: %+v", invalid)
	}
}
