package agent

import "errors"

var (
	ErrRunnerOwnershipRequired         = errors.New("runner ownership context is required")
	ErrRunnerOwnershipMismatch         = errors.New("runner ownership context does not match")
	ErrRunnerProcessControlUnavailable = errors.New("runner process control is unavailable")
	ErrRunnerControllerNotClaimed      = errors.New("runner process controller is not claimed")
	ErrRunnerAlreadyPrepared           = errors.New("runner process is already prepared")
	ErrRunnerAlreadyRunning            = errors.New("runner process is already running")
	ErrRunnerNotPrepared               = errors.New("runner process is not prepared")
	ErrRunnerExecutableMismatch        = errors.New("runner executable is not the configured executable")
	ErrRunnerWorkspaceInvalid          = errors.New("runner workspace is outside the configured root")
	ErrRunnerProcessOwnershipMismatch  = errors.New("runner process identity does not match")
	ErrRunnerProcessStillRunning       = errors.New("runner process is still running")
	ErrRunnerStopTimedOut              = errors.New("runner process stop timed out")
)
