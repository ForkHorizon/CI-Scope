// Starts the local gate worker when its settings are present.
package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strconv"
	"sync"

	"github.com/forkhorizon/ci-scope/agent"
)

const (
	envGatesRoot     = "CI_SCOPE_GATES_ROOT"
	envGatesSHA      = "CI_SCOPE_GATES_SHA"
	envGateWorkspace = "CI_SCOPE_GATE_WORKSPACE"
	// How many pull requests this device checks at once (default 1). Jobs of one repository never run together.
	envGateParallel = "CI_SCOPE_GATE_PARALLEL"
	maxGateParallel = 8
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
	parallel, err := gateParallel(os.Getenv(envGateParallel))
	if err != nil {
		return nil, err
	}
	// One runner for all loops: it holds the locks that keep parallel jobs off each other's checkouts.
	worker := agent.NewLocalGateWorker(client, agent.NewGateScriptRunner(workspace, root, sha))
	worker.Capabilities = detectCapabilities(lookPathOnSystem)
	loopContext, cancel := context.WithCancel(ctx)
	var loops sync.WaitGroup
	for range parallel {
		loops.Go(func() { worker.Loop(loopContext) })
	}
	return func() {
		cancel()
		loops.Wait()
	}, nil
}

func gateParallel(value string) (int, error) {
	if value == "" {
		return 1, nil
	}
	n, err := strconv.Atoi(value)
	if err != nil || n < 1 || n > maxGateParallel {
		return 0, fmt.Errorf("%s must be a number from 1 to %d", envGateParallel, maxGateParallel)
	}
	return n, nil
}
