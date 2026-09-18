package agent

import (
	"context"
	"fmt"
)

type OperationMeta struct {
	OperationID        string
	ExpectedState      State
	LocalEpoch         uint64
	ServerSessionEpoch uint64
}

type AsyncResult[T any] struct {
	OperationID        string
	ExpectedState      State
	LocalEpoch         uint64
	ServerSessionEpoch uint64
	Value              T
	Err                error
}

func (r AsyncResult[T]) IsStale(snapshot StateSnapshot) bool {
	return r.LocalEpoch != snapshot.LocalEpoch || r.ServerSessionEpoch != snapshot.ServerSessionEpoch
}

func StartOperation[T any](ctx context.Context, meta OperationMeta, worker func(context.Context) (T, error)) <-chan AsyncResult[T] {
	result := make(chan AsyncResult[T], 1)
	go func() {
		value, err := worker(ctx)
		result <- AsyncResult[T]{OperationID: meta.OperationID, ExpectedState: meta.ExpectedState, LocalEpoch: meta.LocalEpoch, ServerSessionEpoch: meta.ServerSessionEpoch, Value: value, Err: err}
	}()
	return result
}

func SubmitAsyncResult[T any](ctx context.Context, owner *StateOwner, result AsyncResult[T], apply func(StateSnapshot, T) (State, error)) <-chan TransitionResult {
	reply := make(chan TransitionResult, 1)
	go func() {
		if result.Err != nil {
			reply <- TransitionResult{OperationID: result.OperationID, Err: result.Err}
			return
		}
		command := ownerCommand{operationID: result.OperationID, localEpoch: result.LocalEpoch, serverEpoch: result.ServerSessionEpoch, reply: reply, apply: func(snapshot StateSnapshot) (State, error) {
			if result.ExpectedState != "" && result.ExpectedState != snapshot.State {
				return snapshot.State, fmt.Errorf("expected state %s, got %s", result.ExpectedState, snapshot.State)
			}
			return apply(snapshot, result.Value)
		}}
		sendStateCommand(ctx, owner.commands, command, reply, result.OperationID)
	}()
	return reply
}
