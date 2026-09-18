package agent

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

type ProcessIdentity struct {
	PID              int
	StartTime        int64
	ProcessGroupID   int
	Executable       string
	RunnerInstanceID string
}

func (p ProcessIdentity) Matches(observed ProcessIdentity) bool {
	return p.PID == observed.PID && p.StartTime == observed.StartTime &&
		p.ProcessGroupID == observed.ProcessGroupID &&
		p.Executable == observed.Executable && p.RunnerInstanceID == observed.RunnerInstanceID
}

func ValidateWorkspace(root, target string) error {
	rootAbs, err := filepath.Abs(root)
	if err != nil {
		return err
	}
	targetAbs, err := filepath.Abs(target)
	if err != nil {
		return err
	}
	rootReal, err := filepath.EvalSymlinks(rootAbs)
	if err != nil {
		return err
	}
	if info, err := os.Lstat(targetAbs); err == nil && info.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("workspace target is a symlink")
	}
	targetReal := targetAbs
	if _, err := os.Stat(targetAbs); err == nil {
		targetReal, err = filepath.EvalSymlinks(targetAbs)
		if err != nil {
			return err
		}
	}
	rel, err := filepath.Rel(rootReal, targetReal)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) || filepath.IsAbs(rel) {
		return fmt.Errorf("workspace is outside allowlisted root")
	}
	return nil
}

func CleanupWorkspace(root, target string) error {
	if err := ValidateWorkspace(root, target); err != nil {
		return err
	}
	return os.RemoveAll(target)
}
