package agent

import (
	"context"
	"errors"
	"path/filepath"
	"testing"
)

func TestHeadlessSchedulerReconcilesAmbiguousRunnerObserve(t *testing.T) {
	plane := &schedulerTestPlane{
		status:       []SchedulerStatusResponse{{State: "running", JobState: "in_progress"}},
		observeError: errors.New("external_control_ambiguous"),
	}
	runtime, controller := schedulerTestRuntime(t, plane)
	scheduler, _ := newTestScheduler(t, runtime, plane)
	record := &schedulerRecord{Reservation: schedulerTestReservation(), Phase: schedulerPhaseRunning}
	ownership := testRunnerOwnership()
	if err := controller.Claim(context.Background(), ownership); err != nil {
		t.Fatal(err)
	}
	if err := controller.Prepare(context.Background(), ownership, RunnerPrepareRequest{
		Executable: controller.config.Executable,
		JITConfig:  "jit",
		Workspace:  filepath.Join(controller.config.WorkspaceRoot, "workspace"),
	}); err != nil {
		t.Fatal(err)
	}
	if err := controller.Start(context.Background(), ownership); err != nil {
		t.Fatal(err)
	}
	runtime.mu.Lock()
	runtime.runnerInstanceID = record.Reservation.Correlation.RunnerInstanceID
	runtime.mu.Unlock()
	command, err := scheduler.runnerCommand(record)
	if err != nil {
		t.Fatal(err)
	}
	if err := scheduler.running(context.Background(), record, command); err != nil {
		t.Fatal(err)
	}
	if record.Phase != schedulerPhaseReconcileStart {
		t.Fatalf("running phase = %q, want reconcile_start", record.Phase)
	}
}

func TestHeadlessSchedulerTreatsAmbiguousRunnerStopAsAwaitingRemoval(t *testing.T) {
	plane := &schedulerTestPlane{stopError: errors.New("external_control_ambiguous")}
	runtime, controller := schedulerTestRuntime(t, plane)
	scheduler, _ := newTestScheduler(t, runtime, plane)
	record := &schedulerRecord{Reservation: schedulerTestReservation(), Phase: schedulerPhaseStopping}
	ownership := testRunnerOwnership()
	if err := controller.Claim(context.Background(), ownership); err != nil {
		t.Fatal(err)
	}
	if err := controller.Prepare(context.Background(), ownership, RunnerPrepareRequest{
		Executable: controller.config.Executable,
		JITConfig:  "jit",
		Workspace:  filepath.Join(controller.config.WorkspaceRoot, "workspace"),
	}); err != nil {
		t.Fatal(err)
	}
	if err := controller.Start(context.Background(), ownership); err != nil {
		t.Fatal(err)
	}
	runtime.mu.Lock()
	runtime.runnerInstanceID = record.Reservation.Correlation.RunnerInstanceID
	runtime.mu.Unlock()
	command, err := scheduler.runnerCommand(record)
	if err != nil {
		t.Fatal(err)
	}
	if err := scheduler.stop(context.Background(), record, command); err != nil {
		t.Fatal(err)
	}
	if record.Phase != schedulerPhaseAwaitingRemoval || !record.LocalReleased {
		t.Fatalf("stop record = %+v, want awaiting_removal/local released", record)
	}
}

func TestHeadlessSchedulerDrainGatesClaims(t *testing.T) {
	plane := &schedulerTestPlane{}
	runtime, _ := schedulerTestRuntime(t, plane)
	runtime.mu.Lock()
	runtime.lease.draining = true
	runtime.mu.Unlock()
	scheduler, _ := newTestScheduler(t, runtime, plane)
	if err := scheduler.RunOnce(context.Background()); err != nil {
		runtime.mu.Lock()
		lease := runtime.lease
		runtime.mu.Unlock()
		t.Fatalf("prepare failed: %v lease=%+v", err, lease)
	}
	plane.mu.Lock()
	defer plane.mu.Unlock()
	if plane.claimCalls != 0 {
		t.Fatalf("claim calls while draining = %d", plane.claimCalls)
	}
}

func TestSchedulerReservationValidationRejectsMismatchedToken(t *testing.T) {
	reservation := schedulerTestReservation()
	reservation.Correlation.ReservationToken = "different"
	if err := validateSchedulerReservation(reservation); err == nil {
		t.Fatal("mismatched reservation token was accepted")
	}
}
