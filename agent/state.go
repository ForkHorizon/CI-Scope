package agent

type State string

const (
	StateStarting        State = "STARTING"
	StateRecovering      State = "RECOVERING"
	StateReady           State = "READY"
	StatePausedNoControl State = "PAUSED_NO_CONTROL"
	StateDraining        State = "DRAINING"
	StateDormant         State = "DORMANT"
	StateRecoveryBlocked State = "RECOVERY_BLOCKED"
)

var transitionTable = map[State]map[State]bool{
	StateStarting:        {StateRecovering: true, StateRecoveryBlocked: true},
	StateRecovering:      {StateReady: true, StatePausedNoControl: true, StateDraining: true, StateRecoveryBlocked: true},
	StateReady:           {StatePausedNoControl: true, StateDraining: true, StateRecovering: true},
	StatePausedNoControl: {StateReady: true, StateDraining: true, StateRecovering: true},
	StateDraining:        {StateDormant: true, StateRecoveryBlocked: true},
	StateDormant:         {StateStarting: true},
	StateRecoveryBlocked: {StateRecovering: true},
}

func validState(s State) bool {
	_, ok := transitionTable[s]
	return ok
}

func validTransition(from, to State) bool {
	return transitionTable[from][to]
}
