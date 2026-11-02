package main

import (
	"context"
	"errors"
	"os"

	"github.com/forkhorizon/ci-scope/agent"
)

const (
	envGatesRoot     = "CI_SCOPE_GATES_ROOT"
	envGatesSHA      = "CI_SCOPE_GATES_SHA"
	envGateWorkspace = "CI_SCOPE_GATE_WORKSPACE"
)

// startLocalGateWorker runs pull request checks from the server queue on this device. It stays off unless
// all three settings are present, so installing the agent never starts checking pull requests by itself.
func startLocalGateWorker(ctx context.Context, server *agent.SchedulerServerClient) (func(), error) {
	root, sha, workspace := os.Getenv(envGatesRoot), os.Getenv(envGatesSHA), os.Getenv(envGateWorkspace)
	if root == "" && sha == "" && workspace == "" {
		return func() {}, nil
	}
	if root == "" || sha == "" || workspace == "" {
		return nil, errors.New(envGatesRoot + ", " + envGatesSHA + " and " + envGateWorkspace + " must be set together")
	}
	client, err := agent.NewLocalGateClient(server)
	if err != nil {
		return nil, err
	}
	worker := agent.NewLocalGateWorker(client, agent.NewGateScriptRunner(workspace, root, sha))
	loopContext, cancel := context.WithCancel(ctx)
	done := make(chan struct{})
	go func() {
		defer close(done)
		worker.Loop(loopContext)
	}()
	return func() {
		cancel()
		<-done
	}, nil
}
