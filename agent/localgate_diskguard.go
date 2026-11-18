// Stops a gate command that fills the disk: a runaway test once wrote a 121 GB log into its checkout.
package agent

import (
	"fmt"
	"io/fs"
	"os/exec"
	"path/filepath"
	"strings"
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
	if used, biggest := directoryBytes(dir); used > maxWorkspaceBytes {
		return fmt.Sprintf("the checkout grew to %d GB (limit %d GB), largest file %s: a test or build is writing without bound",
			used>>30, maxWorkspaceBytes>>30, biggest)
	}
	var stat syscall.Statfs_t
	if syscall.Statfs(dir, &stat) == nil {
		if free := int64(stat.Bavail) * int64(stat.Bsize); free < minFreeBytes {
			return fmt.Sprintf("only %d MB of disk is left (minimum %d MB)", free>>20, minFreeBytes>>20)
		}
	}
	return ""
}

// directoryBytes is the space the files under dir really take (allocated blocks, so a sparse file counts only what
// it has written and a hard link counts once), plus the name of the largest file for the error message.
func directoryBytes(dir string) (int64, string) {
	var total, largest int64
	var biggest string
	type fileID struct{ dev, ino uint64 }
	linked := map[fileID]bool{}
	_ = filepath.WalkDir(dir, func(path string, entry fs.DirEntry, err error) error {
		if err != nil || entry.IsDir() {
			return nil // a file that vanished mid-walk is not a problem
		}
		info, infoErr := entry.Info()
		if infoErr != nil {
			return nil
		}
		size := info.Size()
		if stat, ok := info.Sys().(*syscall.Stat_t); ok {
			size = stat.Blocks * 512
			if stat.Nlink > 1 {
				id := fileID{uint64(stat.Dev), stat.Ino}
				if linked[id] {
					return nil
				}
				linked[id] = true
			}
		}
		total += size
		if size > largest {
			largest, biggest = size, strings.TrimPrefix(path, dir+"/")
		}
		return nil
	})
	return total, biggest
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
