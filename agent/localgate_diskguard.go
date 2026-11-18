// Stops a gate command that fills the disk: a runaway test once wrote a 121 GB log into its checkout.
package agent

import (
	"fmt"
	"io/fs"
	"os/exec"
	"path/filepath"
	"syscall"
	"time"
)

// Limits are variables so tests can shrink them. A job that grows its checkout past maxWorkspaceBytes, or leaves the
// disk with less than minFreeBytes, is killed and the checkout cleaned.
var (
	maxWorkspaceBytes int64 = 8 << 30
	minFreeBytes      int64 = 5 << 30
	diskGuardInterval       = 5 * time.Second
)

// diskOverrun says why a command must stop, or "" while it is within limits.
func diskOverrun(dir string) string {
	if used := directoryBytes(dir); used > maxWorkspaceBytes {
		return fmt.Sprintf("the checkout grew to %d GB (limit %d GB): a test or build is writing without bound", used>>30, maxWorkspaceBytes>>30)
	}
	var stat syscall.Statfs_t
	if syscall.Statfs(dir, &stat) == nil {
		if free := int64(stat.Bavail) * int64(stat.Bsize); free < minFreeBytes {
			return fmt.Sprintf("only %d MB of disk is left (minimum %d MB)", free>>20, minFreeBytes>>20)
		}
	}
	return ""
}

func directoryBytes(dir string) int64 {
	var total int64
	_ = filepath.WalkDir(dir, func(_ string, entry fs.DirEntry, err error) error {
		if err != nil || entry.IsDir() {
			return nil // a file that vanished mid-walk is not a problem
		}
		if info, infoErr := entry.Info(); infoErr == nil {
			total += info.Size()
		}
		return nil
	})
	return total
}

// guardDisk watches dir while command runs and kills its process group on an overrun. It returns the reason (or "")
// once stop is closed.
func guardDisk(dir string, command *exec.Cmd, stop <-chan struct{}) <-chan string {
	result := make(chan string, 1)
	go func() {
		ticker := time.NewTicker(diskGuardInterval)
		defer ticker.Stop()
		for {
			select {
			case <-stop:
				result <- ""
				return
			case <-ticker.C:
				if reason := diskOverrun(dir); reason != "" {
					_ = syscall.Kill(-command.Process.Pid, syscall.SIGKILL)
					result <- reason
					return
				}
			}
		}
	}()
	return result
}
