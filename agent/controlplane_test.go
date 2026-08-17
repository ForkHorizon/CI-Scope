package agent

import "testing"

func TestFakeControlPlaneIdempotencySurvivesLostResponse(t *testing.T) {
	plane := NewFakeControlPlane()
	plane.LoseNextResponse("request-1")
	request := ControlRequest{RequestID: "request-1", SessionEpoch: 4, PayloadHash: "hash"}
	if _, err := plane.Handle(request); err != ErrResponseLost {
		t.Fatalf("expected lost response, got %v", err)
	}
	response, err := plane.Handle(request)
	if err != nil || response.ServerRevision != 1 || plane.EffectCount(request.RequestID) != 1 {
		t.Fatalf("response=%+v err=%v effects=%d", response, err, plane.EffectCount(request.RequestID))
	}
}
