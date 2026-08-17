package agent

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

type preparedRunnerProcess struct {
	directory    string
	jitPath      string
	executable   string
	runnerScript string
	workspace    string
	environment  map[string]string
}

func (c *MacOSRunnerProcessController) Prepare(ctx context.Context, ownership RunnerOwnership, request RunnerPrepareRequest) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if err := c.checkLocked(ownership); err != nil {
		return err
	}
	if err := contextError(ctx); err != nil {
		return err
	}
	if c.prepared != nil {
		return ErrRunnerAlreadyPrepared
	}
	prepared, err := c.prepareRunner(request)
	if err != nil {
		return err
	}
	c.prepared = prepared
	return nil
}

func (c *MacOSRunnerProcessController) prepareRunner(request RunnerPrepareRequest) (*preparedRunnerProcess, error) {
	runnerScript, err := c.validatePrepareRequest(request)
	if err != nil {
		return nil, err
	}
	directory, jitPath, err := c.writePrivateJIT(request.JITConfig)
	if err != nil {
		return nil, err
	}
	environment := AllowlistedEnvironment(c.config.Environment, allowAllEnvironmentKeys(c.config.Environment))
	for key, value := range AllowlistedEnvironment(request.Environment, c.config.AllowedEnvironment) {
		environment[key] = value
	}
	return &preparedRunnerProcess{
		directory: directory, jitPath: jitPath, executable: request.Executable,
		runnerScript: runnerScript, workspace: request.Workspace, environment: environment,
	}, nil
}

func (c *MacOSRunnerProcessController) validatePrepareRequest(request RunnerPrepareRequest) (string, error) {
	if request.Executable != c.config.Executable {
		return "", ErrRunnerExecutableMismatch
	}
	runnerScript := strings.TrimSpace(request.RunnerScript)
	if runnerScript == "" {
		runnerScript = c.config.RunnerScript
	}
	if runnerScript != c.config.RunnerScript {
		return "", errors.New("runner script is not the configured script")
	}
	if strings.TrimSpace(request.JITConfig) == "" || strings.TrimSpace(request.Workspace) == "" {
		return "", errors.New("JIT config and workspace are required")
	}
	if err := ValidateWorkspace(c.config.WorkspaceRoot, request.Workspace); err != nil {
		return "", fmt.Errorf("%w: %v", ErrRunnerWorkspaceInvalid, err)
	}
	if err := validateRunnerScript(c.config.WorkspaceRoot, runnerScript); err != nil {
		return "", fmt.Errorf("%w: %v", ErrRunnerWorkspaceInvalid, err)
	}
	return runnerScript, nil
}

func (c *MacOSRunnerProcessController) writePrivateJIT(jitConfig string) (string, string, error) {
	directory, err := os.MkdirTemp(c.config.TempRoot, ".ci-scope-runner-")
	if err != nil {
		return "", "", fmt.Errorf("create private runner directory: %w", err)
	}
	cleanup := func() { _ = os.RemoveAll(directory) }
	if err := os.Chmod(directory, 0o700); err != nil {
		cleanup()
		return "", "", fmt.Errorf("secure private runner directory: %w", err)
	}
	file, err := os.OpenFile(filepath.Join(directory, "jitconfig"), os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		cleanup()
		return "", "", fmt.Errorf("create private JIT config: %w", err)
	}
	jitPath := file.Name()
	if _, err := file.WriteString(jitConfig); err != nil {
		_ = file.Close()
		cleanup()
		return "", "", fmt.Errorf("write private JIT config: %w", err)
	}
	if err := file.Sync(); err != nil {
		_ = file.Close()
		cleanup()
		return "", "", fmt.Errorf("sync private JIT config: %w", err)
	}
	if err := file.Close(); err != nil {
		cleanup()
		return "", "", fmt.Errorf("close private JIT config: %w", err)
	}
	if info, err := os.Lstat(jitPath); err != nil || info.Mode()&os.ModeSymlink != 0 || info.Mode().Perm() != 0o600 {
		cleanup()
		if err != nil {
			return "", "", fmt.Errorf("verify private JIT config: %w", err)
		}
		return "", "", errors.New("private JIT config has unsafe metadata")
	}
	return directory, jitPath, nil
}

func allowAllEnvironmentKeys(environment map[string]string) map[string]bool {
	allowed := make(map[string]bool, len(environment))
	for key := range environment {
		allowed[key] = true
	}
	return allowed
}

func validateConfiguredExecutable(path string) error {
	info, err := os.Lstat(path)
	if err != nil {
		return fmt.Errorf("runner executable: %w", err)
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.Mode().IsRegular() || info.Mode()&0o111 == 0 {
		return errors.New("runner executable must be a regular non-symlink executable")
	}
	return nil
}

func validateRunnerScript(root, script string) error {
	if err := ValidateWorkspace(root, script); err != nil {
		return fmt.Errorf("runner script is outside the configured workspace root: %w", err)
	}
	info, err := os.Lstat(script)
	if err != nil {
		return fmt.Errorf("runner script: %w", err)
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.Mode().IsRegular() || info.Mode()&0o111 == 0 {
		return errors.New("runner script must be a regular non-symlink executable")
	}
	return nil
}
