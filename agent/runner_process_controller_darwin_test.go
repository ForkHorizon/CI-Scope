//go:build darwin

package agent

import (
	"os/exec"
	"syscall"
	"testing"
)

func TestReadRunnerStartTimeForStartedChild(t *testing.T) {
	command := exec.Command("/bin/bash", "-c", "sleep 2")
	command.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := command.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() {
		_ = command.Process.Kill()
		_, _ = command.Process.Wait()
	}()
	startTime, err := readRunnerStartTime(command.Process.Pid)
	if err != nil {
		t.Fatal(err)
	}
	if startTime <= 0 {
		t.Fatalf("start time = %d, want positive value", startTime)
	}
}
