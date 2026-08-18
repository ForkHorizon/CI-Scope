package agent

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestHeadlessSchedulerClearsReservationMissingAfterRestart(t *testing.T) {
	plane := &schedulerTestPlane{
		statusError:  errors.New("operation_not_found"),
		recoverError: errors.New("operation_not_found"),
	}
	runtime, _ := schedulerTestRuntime(t, plane)
	scheduler, store := newTestScheduler(t, runtime, plane)
	if err := scheduler.persist(&schedulerRecord{Reservation: schedulerTestReservation(), Phase: schedulerPhaseReconcileStart}); err != nil {
		t.Fatal(err)
	}
	if err := scheduler.RunOnce(context.Background()); err != nil {
		t.Fatal(err)
	}
	if scheduler.current() != nil {
		t.Fatal("missing server reservation was retained after restart reconciliation")
	}
	value, err := store.GetMetadata(context.Background(), schedulerMetadataKey)
	if err != nil {
		t.Fatal(err)
	}
	if value != "{}" {
		t.Fatalf("scheduler metadata = %q, want empty marker", value)
	}
}

func TestHeadlessSchedulerClearsLocallyReleasedReservationHiddenByNewSession(t *testing.T) {
	plane := &schedulerTestPlane{statusError: errors.New("operation_not_found")}
	runtime, _ := schedulerTestRuntime(t, plane)
	scheduler, _ := newTestScheduler(t, runtime, plane)
	if err := scheduler.persist(&schedulerRecord{
		Reservation:   schedulerTestReservation(),
		Phase:         schedulerPhaseReconcileRelease,
		LocalReleased: true,
	}); err != nil {
		t.Fatal(err)
	}
	if err := scheduler.RunOnce(context.Background()); err != nil {
		t.Fatal(err)
	}
	if scheduler.current() != nil {
		t.Fatal("locally released reservation was retained after session fencing")
	}
}

func TestHeadlessSchedulerReconcilesLostJITWithoutBlindReplay(t *testing.T) {
	plane := &schedulerTestPlane{losePrepareOnce: true}
	runtime, controller := schedulerTestRuntime(t, plane)
	scheduler, store := newTestScheduler(t, runtime, plane)
	if err := scheduler.RunOnce(context.Background()); err != nil {
		t.Fatal(err)
	}
	if err := scheduler.RunOnce(context.Background()); err == nil {
		t.Fatal("lost prepare response did not preserve retry error")
	}
	if _, err := store.GetMetadata(context.Background(), schedulerMetadataKey); err != nil {
		t.Fatal(err)
	}
	// Restart loads reconcile_prepare and must use the server's recovery result.
	scheduler.Close()
	restarted, err := NewHeadlessScheduler(HeadlessSchedulerConfig{
		Runtime: runtime, Store: store, Server: scheduler.config.Server,
		RunnerExecutable: controller.config.Executable, RunnerWorkspace: controller.config.WorkspaceRoot,
		PollInterval: time.Second,
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := restarted.RunOnce(context.Background()); err != nil {
		t.Fatal(err)
	}
	plane.mu.Lock()
	prepareCalls, configAckCalls := plane.prepareCalls, plane.configAckCalls
	plane.mu.Unlock()
	if prepareCalls != 1 {
		t.Fatalf("prepare calls = %d, want one; lost JIT must reconcile by preparation ID", prepareCalls)
	}
	if configAckCalls != 1 {
		t.Fatalf("config ack calls = %d, want one recovered prepare", configAckCalls)
	}
}

func TestHeadlessSchedulerRestartReconcilesStoppingWithoutOldRunnerOwnership(t *testing.T) {
	plane := &schedulerTestPlane{status: []SchedulerStatusResponse{{State: "running", JobState: "in_progress"}}}
	runtime, _ := schedulerTestRuntime(t, plane)
	scheduler, store := newTestScheduler(t, runtime, plane)
	if err := scheduler.persist(&schedulerRecord{Reservation: schedulerTestReservation(), Phase: schedulerPhaseStopping}); err != nil {
		t.Fatal(err)
	}

	restarted, err := NewHeadlessScheduler(HeadlessSchedulerConfig{
		Runtime: runtime, Store: store, Server: scheduler.config.Server,
		RunnerExecutable: scheduler.config.RunnerExecutable, RunnerWorkspace: scheduler.config.RunnerWorkspace,
		PollInterval: 100 * time.Millisecond,
	})
	if err != nil {
		t.Fatal(err)
	}
	if got := restarted.current(); got == nil || got.Phase != schedulerPhaseReconcileStart {
		t.Fatalf("restarted phase = %+v, want reconcile_start", got)
	}
	if err := restarted.RunOnce(context.Background()); err != nil {
		t.Fatal(err)
	}
	if restarted.current() != nil {
		t.Fatal("restart reconciliation retained reservation after server recovery")
	}
}

func TestHeadlessSchedulerShutdownStopsAndReleasesActiveRunner(t *testing.T) {
	plane := &schedulerTestPlane{status: []SchedulerStatusResponse{{State: "completed", JobState: "completed", Terminal: true}}}
	runtime, _ := schedulerTestRuntime(t, plane)
	scheduler, _ := newTestScheduler(t, runtime, plane)
	scheduler.config.PollInterval = 100 * time.Millisecond
	for i := 0; i < 3; i++ {
		if err := scheduler.RunOnce(context.Background()); err != nil {
			t.Fatalf("RunOnce %d: %v", i, err)
		}
	}
	if err := scheduler.Shutdown(context.Background()); err != nil {
		t.Fatal(err)
	}
	if scheduler.current() != nil {
		t.Fatal("graceful shutdown retained active reservation")
	}
	plane.mu.Lock()
	releaseCalls := plane.releaseCalls
	plane.mu.Unlock()
	if releaseCalls != 1 {
		t.Fatalf("release calls = %d, want one", releaseCalls)
	}
}

func TestHeadlessSchedulerLocalStopDoesNotReleaseSlot(t *testing.T) {
	plane := &schedulerTestPlane{status: []SchedulerStatusResponse{{State: "running", JobState: "in_progress"}}}
	runtime, controller := schedulerTestRuntime(t, plane)
	scheduler, _ := newTestScheduler(t, runtime, plane)
	if err := scheduler.RunOnce(context.Background()); err != nil { // claim
		t.Fatal(err)
	}
	if err := scheduler.RunOnce(context.Background()); err != nil { // prepare
		t.Fatal(err)
	}
	if err := scheduler.RunOnce(context.Background()); err != nil { // start
		t.Fatal(err)
	}
	record := scheduler.current()
	if record == nil {
		t.Fatal("missing active scheduler record")
	}
	command, err := scheduler.runnerCommand(record)
	if err != nil {
		t.Fatal(err)
	}
	command.Command = "runner.stop"
	command.OperationID = "operator-stop"
	response, err := runtime.schedulerDispatch("operator-stop", command)
	if err != nil || response.Outcome != "succeeded" {
		t.Fatalf("local stop response = %+v, err=%v", response, err)
	}
	if err := scheduler.RunOnce(context.Background()); err != nil { // server still says running
		t.Fatal(err)
	}
	plane.mu.Lock()
	defer plane.mu.Unlock()
	if plane.releaseCalls != 0 {
		t.Fatalf("release calls after local stop = %d", plane.releaseCalls)
	}
	if controller.prepared == nil {
		// The scheduler has not reached the terminal/removal release barrier.
		t.Fatal("controller unexpectedly released before server terminal/removal evidence")
	}
}
