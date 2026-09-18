package agent

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

type fakeRunnerController struct {
	outcome RunnerStopOutcome
	err     error
}

func (f fakeRunnerController) EmergencyStop(context.Context, string) (RunnerStopOutcome, error) {
	return f.outcome, f.err
}

func blockRuntimeOwner(t *testing.T, runtime *UnixSocketRuntime) func() {
	t.Helper()
	entered := make(chan struct{})
	release := make(chan struct{})
	var releaseOnce sync.Once
	t.Cleanup(func() { releaseOnce.Do(func() { close(release) }) })
	runtime.owner.commands <- ownerCommand{
		operationID: "block-owner",
		localEpoch:  runtime.config.LocalEpoch,
		serverEpoch: runtime.config.ServerSessionEpoch,
		reply:       make(chan TransitionResult, 1),
		apply: func(StateSnapshot) (State, error) {
			close(entered)
			<-release
			return StateRecovering, nil
		},
	}
	<-entered
	return func() { releaseOnce.Do(func() { close(release) }) }
}

func startRuntimeCloseTransition(t *testing.T, runtime *UnixSocketRuntime, controlToken string) (net.Conn, <-chan error) {
	t.Helper()
	socketPath := filepath.Join("/private/tmp", fmt.Sprintf("ci-scope-close-%d-%d.sock", os.Getpid(), time.Now().UnixNano()))
	t.Cleanup(func() { _ = os.Remove(socketPath) })
	listener, err := net.ListenUnix("unix", &net.UnixAddr{Name: socketPath, Net: "unix"})
	if err != nil {
		t.Fatal(err)
	}
	client, err := net.DialUnix("unix", nil, &net.UnixAddr{Name: socketPath, Net: "unix"})
	if err != nil {
		t.Fatal(err)
	}
	serverConn, err := listener.AcceptUnix()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_ = client.Close()
		_ = serverConn.Close()
		_ = listener.Close()
	})
	if _, err := client.Write(socketRequestFrame(t, "close-resume-1", map[string]any{
		"command": "resume", "appInstanceId": "ui-1", "controlToken": controlToken,
	}, SocketSessionContext{MachineID: "machine-1", BootID: "boot-1", AgentInstanceID: "agent-1", SessionID: "session-1", SessionEpoch: 4}, SocketFencingContext{LocalOwnerEpoch: 7, SessionEpoch: 4, FencingToken: "fence-1"})); err != nil {
		t.Fatal(err)
	}
	go runtime.handleConnection(serverConn)
	closeDone := make(chan error, 1)
	go func() { closeDone <- runtime.Close() }()
	return client, closeDone
}

func TestUnixSocketRuntimeDispatchesLeaseAndStatus(t *testing.T) {
	runtime, _ := runtimeForTest(t, nil)
	info, err := os.Stat(runtime.config.Path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("socket mode = %o", info.Mode().Perm())
	}

	acquired := socketRequest(t, runtime, "acquire-1", map[string]any{"command": "acquireControlLease", "appInstanceId": "ui-1"})
	if acquired.Outcome != "succeeded" || acquired.Error != nil {
		t.Fatalf("acquire response = %+v", acquired)
	}
	var lease struct {
		ControlToken string `json:"controlToken"`
	}
	if err := json.Unmarshal(acquired.Payload, &lease); err != nil || lease.ControlToken == "" {
		t.Fatalf("lease payload = %s", acquired.Payload)
	}

	renewed := socketRequest(t, runtime, "renew-1", map[string]any{"command": "renewControlLease", "appInstanceId": "ui-1", "controlToken": lease.ControlToken})
	if renewed.Outcome != "succeeded" {
		t.Fatalf("renew response = %+v", renewed)
	}
	status := socketRequest(t, runtime, "status-1", map[string]any{"command": "status", "appInstanceId": "ui-1"})
	var projection AgentStatus
	if err := json.Unmarshal(status.Payload, &projection); err != nil {
		t.Fatal(err)
	}
	if status.Outcome != "succeeded" || projection.ControlLeaseActive != true || projection.ReadyToClaim || projection.State != StateRecovering {
		t.Fatalf("status=%+v projection=%+v", status, projection)
	}
}

func TestUnixSocketRuntimeCloseCancelsInFlightTransition(t *testing.T) {
	runtime, _ := runtimeForTest(t, nil)
	acquired := socketRequest(t, runtime, "close-lease-1", map[string]any{"command": "acquireControlLease", "appInstanceId": "ui-1"})
	var lease struct {
		ControlToken string `json:"controlToken"`
	}
	if err := json.Unmarshal(acquired.Payload, &lease); err != nil || lease.ControlToken == "" {
		t.Fatalf("lease payload = %s", acquired.Payload)
	}
	unblock := blockRuntimeOwner(t, runtime)
	client, closeDone := startRuntimeCloseTransition(t, runtime, lease.ControlToken)

	_ = client.SetReadDeadline(time.Now().Add(time.Second))
	responseFrame, err := bufio.NewReader(client).ReadBytes('\n')
	if err != nil {
		t.Fatal("in-flight transition did not receive a terminal response")
	}
	var response SocketResponseEnvelope
	if err := json.Unmarshal(responseFrame[:len(responseFrame)-1], &response); err != nil {
		t.Fatal(err)
	}
	if response.Outcome != "rejected" || response.Error == nil || response.Error.Code != "runtime_closed" {
		code := ""
		if response.Error != nil {
			code = response.Error.Code
		}
		t.Fatalf("cancelled transition response = %+v, error code = %q", response, code)
	}
	unblock()
	select {
	case err := <-closeDone:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("runtime close did not complete")
	}
}

func TestSchedulerLeaseIsIndependentFromOperatorLease(t *testing.T) {
	runtime, _ := runtimeForTest(t, nil)
	if err := runtime.AcquireSchedulerLease(); err != nil {
		t.Fatal(err)
	}
	status := runtime.Status()
	if status.ControlLeaseActive || !status.SchedulerLeaseActive || status.ReadyToClaim {
		t.Fatalf("status=%+v", status)
	}

	envelope, err := runtime.schedulerEnvelope("scheduler-1", socketCommand{Command: "runner.start"})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(string(envelope.Payload), "{") {
		t.Fatalf("scheduler payload=%s", envelope.Payload)
	}
	var command socketCommand
	if err := json.Unmarshal(envelope.Payload, &command); err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(command.AppInstanceID, "agent-scheduler:") || command.ControlToken == "" {
		t.Fatalf("scheduler command=%+v", command)
	}

	acquired := socketRequest(t, runtime, "operator-acquire-1", map[string]any{"command": "acquireControlLease", "appInstanceId": "ui-1"})
	if acquired.Outcome != "succeeded" {
		t.Fatalf("operator lease response=%+v", acquired)
	}
	status = runtime.Status()
	if !status.ControlLeaseActive || !status.SchedulerLeaseActive || status.ReadyToClaim {
		t.Fatalf("combined status=%+v", status)
	}
}

func TestUnixSocketRuntimeLifecycleAndFailClosedEmergencyStop(t *testing.T) {
	runtime, _ := runtimeForTest(t, nil)
	acquired := socketRequest(t, runtime, "acquire-1", map[string]any{"command": "acquireControlLease", "appInstanceId": "ui-1"})
	var lease struct {
		ControlToken string `json:"controlToken"`
	}
	if err := json.Unmarshal(acquired.Payload, &lease); err != nil {
		t.Fatal(err)
	}
	resume := socketRequest(t, runtime, "resume-1", map[string]any{"command": "resume", "appInstanceId": "ui-1", "controlToken": lease.ControlToken})
	if resume.Outcome != "succeeded" || runtime.Status().State != StateReady {
		t.Fatalf("resume=%+v status=%+v", resume, runtime.Status())
	}
	drain := socketRequest(t, runtime, "drain-1", map[string]any{"command": "drain", "appInstanceId": "ui-1", "controlToken": lease.ControlToken})
	if drain.Outcome != "succeeded" || runtime.Status().State != StateDraining {
		t.Fatalf("drain=%+v status=%+v", drain, runtime.Status())
	}
	stop := socketRequest(t, runtime, "stop-1", map[string]any{"command": "emergencyStop", "appInstanceId": "ui-1", "controlToken": lease.ControlToken})
	if stop.Outcome != "ambiguous" || stop.Error == nil || stop.Error.Code != "external_control_unavailable" || runtime.Status().State != StateDraining {
		t.Fatalf("stop=%+v status=%+v", stop, runtime.Status())
	}
}

func TestUnixSocketRuntimeEmergencyStopUsesInjectedCompletedEffect(t *testing.T) {
	runtime, _ := runtimeForTest(t, fakeRunnerController{outcome: RunnerStopCompleted})
	acquired := socketRequest(t, runtime, "acquire-1", map[string]any{"command": "acquireControlLease", "appInstanceId": "ui-1"})
	var lease struct {
		ControlToken string `json:"controlToken"`
	}
	if err := json.Unmarshal(acquired.Payload, &lease); err != nil {
		t.Fatal(err)
	}
	_ = socketRequest(t, runtime, "resume-1", map[string]any{"command": "resume", "appInstanceId": "ui-1", "controlToken": lease.ControlToken})
	_ = socketRequest(t, runtime, "drain-1", map[string]any{"command": "drain", "appInstanceId": "ui-1", "controlToken": lease.ControlToken})
	response := socketRequest(t, runtime, "stop-1", map[string]any{"command": "emergencyStop", "appInstanceId": "ui-1", "controlToken": lease.ControlToken})
	if response.Outcome != "succeeded" || runtime.Status().State != StateDormant {
		t.Fatalf("response=%+v status=%+v", response, runtime.Status())
	}
}
