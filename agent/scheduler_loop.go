package agent

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"time"
)

const (
	schedulerRetryBase = time.Second
	schedulerRetryMax  = 30 * time.Second
)

func (s *HeadlessScheduler) Start(ctx context.Context) {
	if ctx == nil {
		ctx = context.Background()
	}
	ctx, s.cancel = context.WithCancel(ctx)
	s.wg.Add(1)
	go func() {
		defer s.wg.Done()
		for {
			err := s.RunOnce(ctx)
			if err != nil {
				log.Printf("scheduler run failed: %v", err)
			}
			timer := time.NewTimer(s.nextRunDelay(err))
			select {
			case <-ctx.Done():
				if !timer.Stop() {
					select {
					case <-timer.C:
					default:
					}
				}
				return
			case <-timer.C:
			}
		}
	}()
}

func (s *HeadlessScheduler) nextRunDelay(err error) time.Duration {
	if err == nil {
		s.retry = 0
		return s.config.PollInterval
	}
	var requestErr *schedulerRequestError
	if errors.As(err, &requestErr) && requestErr.retryAfterMs > 0 {
		s.retry = 0
		return boundedSchedulerRetryAfter(requestErr.retryAfterMs)
	}
	s.retry++
	delay := schedulerRetryBase
	for attempt := 1; attempt < s.retry && delay < schedulerRetryMax; attempt++ {
		delay *= 2
	}
	if delay > schedulerRetryMax {
		return schedulerRetryMax
	}
	return delay
}

func boundedSchedulerRetryAfter(milliseconds uint64) time.Duration {
	minimum := uint64(schedulerRetryBase / time.Millisecond)
	maximum := uint64(schedulerRetryMax / time.Millisecond)
	if milliseconds < minimum {
		milliseconds = minimum
	}
	if milliseconds > maximum {
		milliseconds = maximum
	}
	return time.Duration(milliseconds) * time.Millisecond
}

func (s *HeadlessScheduler) Close() {
	if s == nil {
		return
	}
	s.stopLoop()
	s.markRestartReconciliation()
}

func (s *HeadlessScheduler) stopLoop() {
	if s.cancel != nil {
		s.cancel()
	}
	s.wg.Wait()
}

// Shutdown stops scheduling and drains the durable reservation while the
// authenticated session is still available. If the process is interrupted
// again, every external side effect has already been fenced by a persisted
// phase and the next boot will reconcile it from the server.

func (s *HeadlessScheduler) Shutdown(ctx context.Context) error {
	if s == nil {
		return nil
	}
	if ctx == nil {
		ctx = context.Background()
	}
	s.stopLoop()
	s.runMu.Lock()
	defer s.runMu.Unlock()
	for {
		if err := ctx.Err(); err != nil {
			return err
		}
		record := s.current()
		if record == nil {
			return nil
		}
		err := s.shutdownOnce(ctx, record)
		if s.current() == nil {
			return nil
		}
		delay := s.config.PollInterval
		if err != nil {
			log.Printf("scheduler shutdown reconciliation pending: %v", err)
			delay = s.nextRunDelay(err)
		} else {
			s.retry = 0
		}
		if !waitScheduler(ctx, delay) {
			return ctx.Err()
		}
	}
}

func waitScheduler(ctx context.Context, delay time.Duration) bool {
	if delay <= 0 {
		delay = time.Millisecond
	}
	timer := time.NewTimer(delay)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-timer.C:
		return true
	}
}

func (s *HeadlessScheduler) RunOnce(ctx context.Context) error {
	s.runMu.Lock()
	defer s.runMu.Unlock()
	if ctx == nil {
		ctx = context.Background()
	}
	// This check is the claim and lifecycle gate. It includes the live server
	// session, explicit local control lease, drain/fence/recovery and process
	// health; no scheduler path is allowed to bypass it.
	if !s.config.Runtime.Status().CanClaim() {
		return nil
	}
	record := s.current()
	if record == nil {
		return s.claim(ctx)
	}
	return s.advance(ctx, record)
}

func (s *HeadlessScheduler) current() *schedulerRecord {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.active == nil {
		return nil
	}
	copy := *s.active
	return &copy
}

func (s *HeadlessScheduler) persist(record *schedulerRecord) error {
	data, err := json.Marshal(record)
	if err != nil {
		return err
	}
	if err := s.config.Store.PutMetadata(context.Background(), schedulerMetadataKey, string(data)); err != nil {
		return err
	}
	s.mu.Lock()
	copy := *record
	s.active = &copy
	s.mu.Unlock()
	return nil
}

func (s *HeadlessScheduler) clear() error {
	// Keep an explicit empty marker instead of deleting state during cleanup.
	if err := s.config.Store.PutMetadata(context.Background(), schedulerMetadataKey, "{}"); err != nil {
		return err
	}
	s.mu.Lock()
	s.active = nil
	s.mu.Unlock()
	return nil
}
