package agent

import "testing"

func TestRecoveryDoesNotBlindlyReplayAmbiguousEffect(t *testing.T) {
	decisions := BuildRecoveryDecisions([]Intent{{ID: "jit", Kind: IntentPrepareJIT, Status: IntentPending}}, map[string]RecoveryObservation{})
	if len(decisions) != 1 || decisions[0].Action != RecoveryObserve {
		t.Fatalf("unexpected decision: %+v", decisions)
	}
}

func TestRecoveryKeepsObservedOwnedRunner(t *testing.T) {
	decisions := BuildRecoveryDecisions([]Intent{{ID: "spawn", Kind: IntentSpawnProcess, Status: IntentPending, RunnerInstanceID: "runner"}}, map[string]RecoveryObservation{"spawn": {RunnerInstanceID: "runner", ProcessOwned: true}})
	if len(decisions) != 1 || decisions[0].Action != RecoveryKeepRunning {
		t.Fatalf("unexpected decision: %+v", decisions)
	}
}
