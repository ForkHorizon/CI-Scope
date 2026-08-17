package agent

import (
	"os"
	"os/exec"
	"syscall"
)

type startedRunnerProcess struct {
	identity ProcessIdentity
	process  *os.Process
	done     chan error
}

type runnerProcessOps struct {
	start            func(*exec.Cmd, string) (*startedRunnerProcess, error)
	alive            func(*startedRunnerProcess) (bool, error)
	validateIdentity func(*startedRunnerProcess) error
	signal           func(*startedRunnerProcess, syscall.Signal) error
}
