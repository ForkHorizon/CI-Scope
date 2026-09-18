package agent

import "sync"

type FakeControlPlane struct {
	mu       sync.Mutex
	revision uint64
	lost     map[string]bool
	seen     map[string]ControlResponse
	effects  map[string]int
}

func NewFakeControlPlane() *FakeControlPlane {
	return &FakeControlPlane{lost: map[string]bool{}, seen: map[string]ControlResponse{}, effects: map[string]int{}}
}

func (f *FakeControlPlane) LoseNextResponse(requestID string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.lost[requestID] = true
}

func (f *FakeControlPlane) Handle(request ControlRequest) (ControlResponse, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if previous, ok := f.seen[request.RequestID]; ok {
		return previous, nil
	}
	f.revision++
	response := ControlResponse{OperationID: "op-" + request.RequestID, ServerRevision: f.revision, Outcome: "accepted", SessionEpoch: request.SessionEpoch}
	f.seen[request.RequestID] = response
	f.effects[request.RequestID]++
	if f.lost[request.RequestID] {
		delete(f.lost, request.RequestID)
		return ControlResponse{}, ErrResponseLost
	}
	return response, nil
}

func (f *FakeControlPlane) EffectCount(requestID string) int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.effects[requestID]
}
