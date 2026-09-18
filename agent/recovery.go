package agent

import "fmt"

func BuildRecoveryDecisions(intents []Intent, observations map[string]RecoveryObservation) []RecoveryDecision {
	decisions := make([]RecoveryDecision, 0, len(intents))
	for _, intent := range intents {
		if intent.Status == IntentAcknowledged {
			continue
		}
		observation, observed := observations[intent.ID]
		decision := RecoveryDecision{IntentID: intent.ID, RunnerInstanceID: intent.RunnerInstanceID}
		switch intent.Kind {
		case IntentSpawnProcess, IntentPrepareJIT:
			if observed && observation.ProcessOwned {
				decision.Action = RecoveryKeepRunning
				decision.Reason = "owned process observed; do not replay side effect"
			} else {
				decision.Action = RecoveryObserve
				decision.Reason = "external side effect is ambiguous; reconcile before retry"
			}
		case IntentStopProcess:
			if observed && observation.ProcessOwned {
				decision.Action = RecoveryStopOrphan
				decision.Reason = "owned process remains after stop intent"
			} else {
				decision.Action = RecoveryObserve
				decision.Reason = "stop result is ambiguous"
			}
		case IntentRemoveRegistration:
			decision.Action = RecoveryRemoveRegistration
			decision.Reason = "registration cleanup must be reconciled by runner ID"
		case IntentReleaseReservation:
			decision.Action = RecoveryReleaseUnassigned
			decision.Reason = "release only after server confirms no assignment"
		case IntentCreateDirectory, IntentCleanupWorkspace:
			decision.Action = RecoveryObserve
			decision.Reason = "path effect requires ownership and symlink-safe observation"
		default:
			decision.Action = RecoveryBlock
			decision.Reason = fmt.Sprintf("unknown intent kind %q", intent.Kind)
		}
		decisions = append(decisions, decision)
	}
	return decisions
}
