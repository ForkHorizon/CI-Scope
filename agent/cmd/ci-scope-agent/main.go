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
	config, ownerLease, err := initBootstrap()
	if err != nil {
		return err
	}
	defer ownerLease.Release()

	rootContext, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	plane, lifecycle, info, err := initControlPlane(rootContext, config)
	if err != nil {
		return err
	}

	runtime, scheduler, cleanup, err := initRuntime(rootContext, config, plane, info, ownerLease)
	if err != nil {
		_, _ = lifecycle.Close(context.Background())
		return err
	}
	defer cleanup()

	return runLoop(rootContext, config, runtime, lifecycle, scheduler)
}

func initBootstrap() (agent.BootstrapConfig, *agent.OwnerLease, error) {
	config, err := agent.LoadBootstrapConfig(nil)
	if err != nil {
		return agent.BootstrapConfig{}, nil, err
	}
	requestID, err := agent.NewSessionRequestID()
	if err != nil {
		return agent.BootstrapConfig{}, nil, fmt.Errorf("generate session request ID: %w", err)
	}
	config.SessionRequestID = requestID
	ownerLease, err := agent.AcquireOwnerLock(config.StateRoot, config.AgentInstanceID)
	if err != nil {
		return agent.BootstrapConfig{}, nil, err
	}
	return config, ownerLease, nil
}

func initControlPlane(ctx context.Context, config agent.BootstrapConfig) (*agent.HTTPControlPlane, *agent.SessionLifecycle, agent.SessionInfo, error) {
	plane, err := agent.NewHTTPControlPlane(config.ControlPlaneURL, &http.Client{Timeout: config.HTTPTimeout}, config.CredentialProof)
	if err != nil {
		return nil, nil, agent.SessionInfo{}, err
	}
	if config.EnrollmentToken != "" {
		if err := enrollDevice(ctx, plane, config); err != nil {
			return nil, nil, agent.SessionInfo{}, err
		}
	}
	lifecycle, err := agent.NewSessionLifecycle(plane, agent.SessionLifecycleConfig{
		MachineID: config.MachineID, BootID: config.BootID, AgentInstanceID: config.AgentInstanceID,
		CredentialID: config.CredentialID, SessionRequestID: config.SessionRequestID, ShadowToken: config.ShadowToken,
	})
	if err != nil {
		return nil, nil, agent.SessionInfo{}, err
	}
	openContext, cancelOpen := context.WithTimeout(ctx, config.HTTPTimeout)
	info, err := lifecycle.Open(openContext)
	cancelOpen()
	if err != nil {
		return nil, nil, agent.SessionInfo{}, err
	}
	return plane, lifecycle, info, nil
}

func enrollDevice(ctx context.Context, plane *agent.HTTPControlPlane, config agent.BootstrapConfig) error {
	enrollmentContext, cancel := context.WithTimeout(ctx, config.HTTPTimeout)
	defer cancel()
	_, err := agent.EnrollDevice(enrollmentContext, plane, agent.EnrollmentConfig{
		Token: config.EnrollmentToken, DeviceSecret: config.DeviceSecret, CredentialID: config.CredentialID,
		MachineID: config.MachineID, BootID: config.BootID, AgentInstanceID: config.AgentInstanceID,
		SessionRequestID: config.SessionRequestID, SessionID: config.SessionRequestID,
		PoolIdentity: config.PoolIdentity, IssuerSecret: config.EnrollmentIssuer,
	})
	return err
}

func initRuntime(ctx context.Context, config agent.BootstrapConfig, plane *agent.HTTPControlPlane, info agent.SessionInfo, ownerLease *agent.OwnerLease) (*agent.UnixSocketRuntime, *agent.HeadlessScheduler, func(), error) {
	controller, err := agent.NewConfiguredRunnerProcessController(agent.MacOSRunnerProcessControllerConfig{
		Executable: config.RunnerExecutable, WorkspaceRoot: config.RunnerWorkspaceRoot, RunnerScript: config.RunnerScript, TempRoot: config.RunnerTempRoot,
		Environment: agent.DefaultRunnerEnvironment(),
	})
	if err != nil {
		return nil, nil, nil, err
	}
	runtime, err := agent.NewUnixSocketRuntime(agent.UnixSocketConfig{
		Path: config.SocketPath, LocalEpoch: ownerLease.Token().LocalEpoch, ServerSessionEpoch: info.Fencing.SessionEpoch,
		Identity: info.Identity, FencingToken: info.Fencing.FenceToken, InitialState: agent.StateReady,
		ProcessAlive: true, SchedulerHealthy: true, ServerConnected: true,
		ControlPlane:      plane,
		ProcessController: controller,
	})
	if err != nil {
		return nil, nil, nil, err
	}
	if err := runtime.Start(ctx); err != nil {
		return nil, nil, nil, err
	}
	if err := runtime.AcquireSchedulerLease(); err != nil {
		_ = runtime.Close()
		return nil, nil, nil, fmt.Errorf("acquire scheduler lease: %w", err)
	}
	if err := agent.WriteSessionDescriptor(config.StateRoot, agent.SessionDescriptor{
		MachineID: config.MachineID, BootID: config.BootID, AgentInstanceID: config.AgentInstanceID,
		SessionID: info.Identity.SessionID, SessionEpoch: info.Fencing.SessionEpoch,
		LocalOwnerEpoch: ownerLease.Token().LocalEpoch, FencingToken: info.Fencing.FenceToken,
		SocketPath: config.SocketPath,
	}); err != nil {
		_ = runtime.Close()
		return nil, nil, nil, err
	}
	scheduler, cleanupScheduler, err := initScheduler(ctx, config, runtime, info)
	if err != nil {
		_ = agent.RemoveSessionDescriptor(config.StateRoot)
		_ = runtime.Close()
		return nil, nil, nil, err
	}
	cleanup := func() {
		cleanupScheduler()
		_ = agent.RemoveSessionDescriptor(config.StateRoot)
		_ = runtime.Close()
	}
	return runtime, scheduler, cleanup, nil
}

func initScheduler(ctx context.Context, config agent.BootstrapConfig, runtime *agent.UnixSocketRuntime, info agent.SessionInfo) (*agent.HeadlessScheduler, func(), error) {
	store, err := agent.OpenSQLiteStore(filepath.Join(config.StateRoot, "agent.sqlite"))
	if err != nil {
		return nil, nil, err
	}
	schedulerServer, err := agent.NewSchedulerServerClient(runtime, info.Identity, info.Fencing, info.Revision)
	if err != nil {
		_ = store.Close()
		return nil, nil, err
	}
	scheduler, err := agent.NewHeadlessScheduler(agent.HeadlessSchedulerConfig{
		Runtime: runtime, Store: store, Server: schedulerServer, PoolIdentity: config.PoolIdentity,
		RunnerExecutable: config.RunnerExecutable, RunnerWorkspace: config.RunnerWorkspaceRoot,
		PollInterval: config.HeartbeatInterval,
	})
	if err != nil {
		_ = store.Close()
		return nil, nil, err
	}
	scheduler.Start(ctx)
	cleanup := func() {
		scheduler.Close()
		_ = store.Close()
	}
	return scheduler, cleanup, nil
}

func runLoop(ctx context.Context, config agent.BootstrapConfig, runtime *agent.UnixSocketRuntime, lifecycle *agent.SessionLifecycle, scheduler *agent.HeadlessScheduler) error {
	ticker := time.NewTicker(config.HeartbeatInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			closeContext, cancelClose := context.WithTimeout(context.Background(), config.HTTPTimeout)
			defer cancelClose()
			shutdownErr := scheduler.Shutdown(closeContext)
			_, closeErr := lifecycle.Close(closeContext)
			if shutdownErr != nil && !errors.Is(shutdownErr, context.Canceled) {
				return shutdownErr
			}
			if closeErr != nil && !errors.Is(closeErr, context.Canceled) {
				return closeErr
			}
			return nil
		case <-ticker.C:
			handleHeartbeat(ctx, config, runtime, lifecycle)
		}
	}
}

func handleHeartbeat(ctx context.Context, config agent.BootstrapConfig, runtime *agent.UnixSocketRuntime, lifecycle *agent.SessionLifecycle) {
	if !runtime.RenewSchedulerLease() {
		if leaseErr := runtime.AcquireSchedulerLease(); leaseErr != nil {
			runtime.SetSchedulerHealthy(false)
			log.Printf("scheduler lease unavailable: %v", leaseErr)
		} else {
			runtime.SetSchedulerHealthy(true)
		}
	}
	lifecycle.ObserveServerRevision(runtime.CurrentServerRevision())
	heartbeatContext, cancel := context.WithTimeout(ctx, config.HTTPTimeout)
	defer cancel()
	heartbeatInfo, heartbeatErr := lifecycle.Heartbeat(heartbeatContext)
	runtime.SetServerConnected(heartbeatErr == nil)
	if heartbeatErr == nil {
		runtime.SetServerRevision(heartbeatInfo.Revision)
	} else {
		log.Printf("session heartbeat failed: %v", heartbeatErr)
	}
}
