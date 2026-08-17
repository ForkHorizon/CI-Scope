package agent

import (
	"context"
	"errors"
	"fmt"
)

func (s *SessionLifecycle) Heartbeat(ctx context.Context) (SessionInfo, error) {
	return s.transition(ctx, "heartbeat")
}

func (s *SessionLifecycle) Close(ctx context.Context) (SessionInfo, error) {
	return s.transition(ctx, "close")
}

func (s *SessionLifecycle) transition(ctx context.Context, name string) (SessionInfo, error) {
	s.mu.Lock()
	if !s.open {
		s.mu.Unlock()
		return SessionInfo{}, errors.New("session is not open")
	}
	identity, fencing, revision := s.identity, s.fencing, s.revision
	s.sequence++
	requestID := fmt.Sprintf("%s.%s.%d", identity.SessionID, name, s.sequence)
	// Lease renewal and close must not be rejected because a scheduler mutation
	// advanced the pool revision between heartbeats. Session fencing remains the
	// authority for these transitions.
	if revision > 0 && name != "heartbeat" && name != "close" {
		fencing.ExpectedServerRevision = &revision
	}
	payload := map[string]any{
		"type": "session." + name, "sessionId": identity.SessionID,
		"sessionEpoch": fencing.SessionEpoch, "fenceToken": fencing.FenceToken,
	}
	request, err := NewServerRequestEnvelope(requestID, identity, fencing, payload)
	s.mu.Unlock()
	if err != nil {
		return SessionInfo{}, err
	}
	path := "/api/ci/v2/sessions/" + identity.SessionID + "/" + name
	response, err := s.plane.Do(ctx, path, request)
	if err != nil {
		return SessionInfo{}, err
	}
	if response.Outcome != "accepted" && response.Outcome != "completed" {
		return SessionInfo{}, fmt.Errorf("session.%s returned %s", name, response.Outcome)
	}
	s.mu.Lock()
	s.revision = response.ServerRevision
	if name == "close" {
		s.open = false
	}
	info := s.infoLocked()
	s.mu.Unlock()
	return info, nil
}

func (s *SessionLifecycle) Info() (SessionInfo, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.open {
		return SessionInfo{}, false
	}
	return s.infoLocked(), true
}

// ObserveServerRevision shares revisions learned by the scheduler/runtime
// with the session heartbeat path, preventing a heartbeat from replaying an
// older optimistic-concurrency baseline after a scheduler mutation.
func (s *SessionLifecycle) ObserveServerRevision(value uint64) {
	if s == nil || value == 0 {
		return
	}
	s.mu.Lock()
	if value > s.revision {
		s.revision = value
	}
	s.mu.Unlock()
}

func (s *SessionLifecycle) infoLocked() SessionInfo {
	return SessionInfo{Identity: s.identity, Fencing: s.fencing, Revision: s.revision}
}
