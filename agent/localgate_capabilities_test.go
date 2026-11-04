// Tests for claiming with device capabilities and recording the config version.
package agent

import (
	"context"
	"encoding/json"
	"reflect"
	"strings"
	"testing"
)

func TestClaimWithSendsCapabilities(t *testing.T) {
	plane := &schedulerEnvelopeTestPlane{response: ServerResponseEnvelope{Outcome: "completed", Payload: mustJSON(map[string]any{"type": "local-gates.claim", "job": nil})}}
	client := newLocalGateTestClient(t, plane)
	if _, err := client.ClaimWith(context.Background(), "lease-9", []string{"xcode", "cargo"}); err != nil {
		t.Fatal(err)
	}
	var payload map[string]any
	if err := json.Unmarshal(plane.request.Payload, &payload); err != nil {
		t.Fatal(err)
	}
	got, _ := payload["capabilities"].([]any)
	if len(got) != 2 || got[0] != "xcode" || got[1] != "cargo" {
		t.Fatalf("capabilities = %#v", payload["capabilities"])
	}
	if _, err := client.Claim(context.Background(), "lease-10"); err != nil {
		t.Fatal(err)
	}
	var plain map[string]any
	if err := json.Unmarshal(plane.request.Payload, &plain); err != nil {
		t.Fatal(err)
	}
	if _, present := plain["capabilities"]; present || len(plain) != 2 {
		t.Fatalf("a claim without capabilities must keep the old payload, got %#v", plain)
	}
}

type capabilityServer struct {
	fakeGateServer
	claimedWith []string
}

func (c *capabilityServer) ClaimWith(_ context.Context, _ string, capabilities []string) (*LocalGateJob, error) {
	c.claimedWith = capabilities
	return c.job, c.claimErr
}

func TestWorkerClaimsWithItsCapabilitiesWhenTheServerSupportsIt(t *testing.T) {
	server := &capabilityServer{fakeGateServer: fakeGateServer{job: &LocalGateJob{ID: "job-1"}}}
	worker := testGateWorker(&server.fakeGateServer, fakeGateRunner{report: LocalGateReport{Status: "passed"}})
	worker.Server = server
	worker.Capabilities = []string{"xcode"}
	if _, err := worker.RunOnce(context.Background()); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(server.claimedWith, []string{"xcode"}) {
		t.Fatalf("claimed with %v", server.claimedWith)
	}
}

func TestWorkerFallsBackToPlainClaimWithoutCapabilities(t *testing.T) {
	server := &capabilityServer{fakeGateServer: fakeGateServer{job: &LocalGateJob{ID: "job-1"}}}
	worker := testGateWorker(&server.fakeGateServer, fakeGateRunner{report: LocalGateReport{Status: "passed"}})
	worker.Server = server
	if _, err := worker.RunOnce(context.Background()); err != nil {
		t.Fatal(err)
	}
	if server.claimedWith != nil {
		t.Fatalf("no capabilities means the plain claim, got %v", server.claimedWith)
	}
}

func TestRunnerRecordsTheConfigVersionFromTheCLI(t *testing.T) {
	out := "CI Scope: PASSED — 1 of 1 checks passed\n" +
		`{"results":[{"id":"protected-files","status":"passed","detail":""}],"configVersion":7}` + "\n"
	commands := &scriptedCommands{gitHead: gatePin, cliOut: out}
	report, err := newScriptedRunner(t, commands).Run(context.Background(), gateJob())
	if err != nil || report.ConfigVersion != 7 {
		t.Fatalf("report = %#v, err = %v", report, err)
	}
	encoded, _ := json.Marshal(report)
	if !strings.Contains(string(encoded), `"configVersion":7`) {
		t.Fatalf("encoded = %s", encoded)
	}
}
