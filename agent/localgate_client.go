// Client for the server's local gate queue: claim, heartbeat and complete.
package agent

import (
	"context"
	"errors"
)

const (
	LocalGateClaimPath     = "/api/ci/v2/local-gates/claim"
	LocalGateHeartbeatPath = "/api/ci/v2/local-gates/heartbeat"
	LocalGateCompletePath  = "/api/ci/v2/local-gates/complete"
)

// LocalGateClient talks to the server's local gate queue through the signed session transport.
type LocalGateClient struct {
	server *SchedulerServerClient
}

func NewLocalGateClient(server *SchedulerServerClient) (*LocalGateClient, error) {
	if server == nil {
		return nil, errors.New("local gate client needs a scheduler server client")
	}
	return &LocalGateClient{server: server}, nil
}

// Claim asks for the next queued job. The lease ID is chosen by the caller and doubles as the request ID,
// so a retried claim is idempotent on the server. A nil job means the queue is empty or busy.
func (c *LocalGateClient) Claim(ctx context.Context, leaseID string) (*LocalGateJob, error) {
	return c.ClaimWith(ctx, leaseID, nil)
}

// ClaimWith is Claim for a device that declares the tools it has (for example xcode), so the server
// only hands it jobs it can run.
func (c *LocalGateClient) ClaimWith(ctx context.Context, leaseID string, capabilities []string) (*LocalGateJob, error) {
	payload := map[string]any{"type": "local-gates.claim", "leaseId": leaseID}
	if len(capabilities) > 0 {
		payload["capabilities"] = capabilities
	}
	response, err := c.server.request(ctx, "local-gate-claim."+leaseID, LocalGateClaimPath, payload)
	if err != nil {
		return nil, err
	}
	var result struct {
		Job *LocalGateJob `json:"job"`
	}
	if err := decodeSchedulerPayload(response, &result); err != nil {
		return nil, err
	}
	return result.Job, nil
}

// Heartbeat extends the lease, tells the server what the run is doing now, and reports whether the run should stop.
func (c *LocalGateClient) Heartbeat(ctx context.Context, requestID, jobID, leaseID, activity string) (bool, error) {
	payload := map[string]any{"type": "local-gates.heartbeat", "jobId": jobID, "leaseId": leaseID}
	if activity != "" {
		payload["activity"] = activity
	}
	response, err := c.server.request(ctx, requestID, LocalGateHeartbeatPath, payload)
	if err != nil {
		return false, err
	}
	var result struct {
		Cancel bool `json:"cancel"`
	}
	if err := decodeSchedulerPayload(response, &result); err != nil {
		return false, err
	}
	return result.Cancel, nil
}

// Complete publishes the report; the stable request ID makes a retry harmless.
func (c *LocalGateClient) Complete(ctx context.Context, jobID, leaseID string, report LocalGateReport) error {
	_, err := c.server.request(ctx, "local-gate-complete."+leaseID, LocalGateCompletePath, map[string]any{
		"type": "local-gates.complete", "jobId": jobID, "leaseId": leaseID, "report": report,
	})
	return err
}
