package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"github.com/forkhorizon/ci-scope/agent"
)

func main() {
	if err := run(); err != nil {
		log.Printf("ci-scope-agent stopped: %v", err)
		os.Exit(1)
	}
}

func run() error {
	config, err := agent.LoadBootstrapConfig(nil)
	if err != nil {
		return err
	}
	requestID, err := agent.NewSessionRequestID()
	if err != nil {
		return fmt.Errorf("generate session request ID: %w", err)
	}
	// The launchd plist provides bootstrap configuration, not a reusable
	// idempotency key. Every Agent boot must open a fresh server session.
	config.SessionRequestID = requestID
	ownerLease, err := agent.AcquireOwnerLock(config.StateRoot, config.AgentInstanceID)
	if err != nil {
		return err
	}
	defer ownerLease.Release()
	rootContext, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	plane, err := agent.NewHTTPControlPlane(config.ControlPlaneURL, &http.Client{Timeout: config.HTTPTimeout}, config.CredentialProof)
	if err != nil {
		return err
	}
	processController, err := agent.NewConfiguredRunnerProcessController(agent.MacOSRunnerProcessControllerConfig{
		Executable: config.RunnerExecutable, WorkspaceRoot: config.RunnerWorkspaceRoot, RunnerScript: config.RunnerScript, TempRoot: config.RunnerTempRoot,
		Environment: agent.DefaultRunnerEnvironment(),
	})
	if err != nil {
		return err
	}
	if config.EnrollmentToken != "" {
		enrollmentContext, cancelEnrollment := context.WithTimeout(rootContext, config.HTTPTimeout)
		_, enrollmentErr := agent.EnrollDevice(enrollmentContext, plane, agent.EnrollmentConfig{
			Token: config.EnrollmentToken, DeviceSecret: config.DeviceSecret, CredentialID: config.CredentialID,
			MachineID: config.MachineID, BootID: config.BootID, AgentInstanceID: config.AgentInstanceID,
			SessionRequestID: config.SessionRequestID, SessionID: config.SessionRequestID,
			PoolIdentity: config.PoolIdentity, IssuerSecret: config.EnrollmentIssuer,
		})
		cancelEnrollment()
		if enrollmentErr != nil {
			return enrollmentErr
		}
	}
	lifecycle, err := agent.NewSessionLifecycle(plane, agent.SessionLifecycleConfig{
		MachineID: config.MachineID, BootID: config.BootID, AgentInstanceID: config.AgentInstanceID,
		CredentialID: config.CredentialID, SessionRequestID: config.SessionRequestID, ShadowToken: config.ShadowToken,
	})
	if err != nil {
		return err
	}
	openContext, cancelOpen := context.WithTimeout(rootContext, config.HTTPTimeout)
	info, err := lifecycle.Open(openContext)
	cancelOpen()
	if err != nil {
		return err
	}

	runtime, err := agent.NewUnixSocketRuntime(agent.UnixSocketConfig{
		Path: config.SocketPath, LocalEpoch: ownerLease.Token().LocalEpoch, ServerSessionEpoch: info.Fencing.SessionEpoch,
		Identity: info.Identity, FencingToken: info.Fencing.FenceToken, InitialState: agent.StateReady,
		ProcessAlive: true, SchedulerHealthy: true, ServerConnected: true,
		ControlPlane:      plane,
		ProcessController: processController,
	})
	if err != nil {
		return err
	}
	if err := runtime.Start(rootContext); err != nil {
		_, _ = lifecycle.Close(context.Background())
		return err
	}
	defer runtime.Close()
	if err := runtime.AcquireSchedulerLease(); err != nil {
		_, _ = lifecycle.Close(context.Background())
		return fmt.Errorf("acquire scheduler lease: %w", err)
	}
	if err := agent.WriteSessionDescriptor(config.StateRoot, agent.SessionDescriptor{
		MachineID: config.MachineID, BootID: config.BootID, AgentInstanceID: config.AgentInstanceID,
		SessionID: info.Identity.SessionID, SessionEpoch: info.Fencing.SessionEpoch,
		LocalOwnerEpoch: ownerLease.Token().LocalEpoch, FencingToken: info.Fencing.FenceToken,
		SocketPath: config.SocketPath,
	}); err != nil {
		_ = runtime.Close()
		_, _ = lifecycle.Close(context.Background())
		return err
	}
	defer func() { _ = agent.RemoveSessionDescriptor(config.StateRoot) }()

	store, err := agent.OpenSQLiteStore(filepath.Join(config.StateRoot, "agent.sqlite"))
	if err != nil {
		return err
	}
	defer store.Close()
	schedulerServer, err := agent.NewSchedulerServerClient(runtime, info.Identity, info.Fencing, info.Revision)
	if err != nil {
		return err
	}
	scheduler, err := agent.NewHeadlessScheduler(agent.HeadlessSchedulerConfig{
		Runtime: runtime, Store: store, Server: schedulerServer, PoolIdentity: config.PoolIdentity,
		RunnerExecutable: config.RunnerExecutable, RunnerWorkspace: config.RunnerWorkspaceRoot,
		PollInterval: config.HeartbeatInterval,
	})
	if err != nil {
		return err
	}
	scheduler.Start(rootContext)
	defer scheduler.Close()

	ticker := time.NewTicker(config.HeartbeatInterval)
	defer ticker.Stop()
	for {
		select {
		case <-rootContext.Done():
			closeContext, cancelClose := context.WithTimeout(context.Background(), config.HTTPTimeout)
			shutdownErr := scheduler.Shutdown(closeContext)
			_, closeErr := lifecycle.Close(closeContext)
			cancelClose()
			if shutdownErr != nil && !errors.Is(shutdownErr, context.Canceled) {
				return shutdownErr
			}
			if closeErr != nil && !errors.Is(closeErr, context.Canceled) {
				return closeErr
			}
			return nil
		case <-ticker.C:
			if !runtime.RenewSchedulerLease() {
				if leaseErr := runtime.AcquireSchedulerLease(); leaseErr != nil {
					runtime.SetSchedulerHealthy(false)
					log.Printf("scheduler lease unavailable: %v", leaseErr)
				} else {
					runtime.SetSchedulerHealthy(true)
				}
			}
			lifecycle.ObserveServerRevision(runtime.CurrentServerRevision())
			heartbeatContext, cancelHeartbeat := context.WithTimeout(rootContext, config.HTTPTimeout)
			heartbeatInfo, heartbeatErr := lifecycle.Heartbeat(heartbeatContext)
			cancelHeartbeat()
			runtime.SetServerConnected(heartbeatErr == nil)
			if heartbeatErr == nil {
				runtime.SetServerRevision(heartbeatInfo.Revision)
			}
			if heartbeatErr != nil {
				log.Printf("session heartbeat failed: %v", heartbeatErr)
			}
		}
	}
}
