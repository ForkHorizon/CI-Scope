package agent

import (
	"context"
	"errors"
	"fmt"
	"sync"
)

type ownerCommand struct {
	operationID string
	localEpoch  uint64
	serverEpoch uint64
	apply       func(StateSnapshot) (State, error)
	reply       chan TransitionResult
}

type StateOwner struct {
	mu                 sync.RWMutex
	state              State
	localEpoch         uint64
	serverSessionEpoch uint64
	commands           chan ownerCommand
}

func NewStateOwner(initial State, localEpoch, serverSessionEpoch uint64) (*StateOwner, error) {
	if !validState(initial) {
		return nil, fmt.Errorf("invalid initial state %q", initial)
	}
	if localEpoch == 0 {
		return nil, errors.New("local epoch must be non-zero")
	}
	return &StateOwner{state: initial, localEpoch: localEpoch, serverSessionEpoch: serverSessionEpoch, commands: make(chan ownerCommand)}, nil
}

// Run is the sole state mutation loop. Workers return values; only commands
// serialized here can change the local state.
func (o *StateOwner) Run(ctx context.Context) error {
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case cmd := <-o.commands:
			o.handle(cmd)
		}
	}
}

func (o *StateOwner) handle(cmd ownerCommand) {
	snapshot := o.Snapshot()
	result := TransitionResult{OperationID: cmd.operationID, State: snapshot.State, LocalEpoch: snapshot.LocalEpoch, ServerSessionEpoch: snapshot.ServerSessionEpoch}
	if cmd.localEpoch != snapshot.LocalEpoch || cmd.serverEpoch != snapshot.ServerSessionEpoch {
		result.Stale = true
		cmd.reply <- result
		return
	}
	next, err := cmd.apply(snapshot)
	if err != nil {
		result.Err = err
		cmd.reply <- result
		return
	}
	o.mu.Lock()
	o.state = next
	o.mu.Unlock()
	result.Applied = true
	result.State = next
	cmd.reply <- result
}

func (o *StateOwner) Snapshot() StateSnapshot {
	o.mu.RLock()
	defer o.mu.RUnlock()
	return StateSnapshot{o.state, o.localEpoch, o.serverSessionEpoch}
}

func (o *StateOwner) Submit(ctx context.Context, request TransitionRequest) <-chan TransitionResult {
	reply := make(chan TransitionResult, 1)
	cmd := ownerCommand{operationID: request.OperationID, localEpoch: request.LocalEpoch, serverEpoch: request.ServerSessionEpoch, reply: reply, apply: func(snapshot StateSnapshot) (State, error) {
		if request.ExpectedState != "" && request.ExpectedState != snapshot.State {
			return snapshot.State, fmt.Errorf("expected state %s, got %s", request.ExpectedState, snapshot.State)
		}
		if !validState(request.To) || !validTransition(snapshot.State, request.To) {
			return snapshot.State, fmt.Errorf("invalid transition %s -> %s", snapshot.State, request.To)
		}
		return request.To, nil
	}}
	go sendStateCommand(ctx, o.commands, cmd, reply, request.OperationID)
	return reply
}

func sendStateCommand(ctx context.Context, commands chan ownerCommand, command ownerCommand, reply chan TransitionResult, operationID string) {
	select {
	case commands <- command:
	case <-ctx.Done():
		reply <- TransitionResult{OperationID: operationID, Err: ctx.Err()}
	}
}
