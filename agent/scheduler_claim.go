package agent

import (
	"context"
	"time"
)

func (s *HeadlessScheduler) claim(ctx context.Context) error {
	intent, err := s.pendingClaimIntent(ctx)
	if err != nil {
		return err
	}
	if intent == nil {
		requestID, err := newSchedulerRequestID("claim")
		if err != nil {
			return err
		}
		intent = &Intent{ID: requestID, OperationID: requestID, Kind: IntentClaimReservation, Status: IntentPending, LocalEpoch: s.config.Runtime.Status().LocalEpoch, Payload: map[string]string{"poolIdentity": s.config.PoolIdentity}, CreatedAt: time.Now().UTC()}
		if err := s.config.Store.PutIntent(ctx, *intent); err != nil {
			return err
		}
	}
	result, err := s.config.Server.ClaimNext(ctx, intent.OperationID, s.config.PoolIdentity)
	if err != nil {
		return err
	}
	if !result.Claimed {
		return s.ackIntent(ctx, *intent)
	}
	record := &schedulerRecord{Reservation: result.Reservation, Phase: schedulerPhaseClaimed, ClaimRequestID: intent.OperationID}
	if err := s.persist(record); err != nil {
		return err
	}
	return s.ackIntent(ctx, *intent)
}

func (s *HeadlessScheduler) pendingClaimIntent(ctx context.Context) (*Intent, error) {
	intents, err := s.config.Store.PendingIntents(ctx)
	if err != nil {
		return nil, err
	}
	for _, intent := range intents {
		if intent.Kind == IntentClaimReservation {
			copy := intent
			return &copy, nil
		}
	}
	return nil, nil
}

func (s *HeadlessScheduler) ackIntent(ctx context.Context, intent Intent) error {
	intent.Status = IntentAcknowledged
	return s.config.Store.PutIntent(ctx, intent)
}
