package agent

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

var ErrUnsafePath = errors.New("unsafe or unallowlisted path")

func ValidateAllowlistedPath(roots []string, target string) error {
	absoluteTarget, err := filepath.Abs(target)
	if err != nil {
		return fmt.Errorf("%w: absolute target: %v", ErrUnsafePath, err)
	}
	resolvedTarget, targetErr := resolveForCheck(absoluteTarget)
	if targetErr != nil {
		return fmt.Errorf("%w: target resolution: %v", ErrUnsafePath, targetErr)
	}
	for _, root := range roots {
		absoluteRoot, rootErr := filepath.Abs(root)
		if rootErr != nil {
			continue
		}
		resolvedRoot, resolveErr := filepath.EvalSymlinks(absoluteRoot)
		if resolveErr != nil {
			continue
		}
		relative, relErr := filepath.Rel(resolvedRoot, resolvedTarget)
		if relErr == nil && relative != "." && relative != ".." && !strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
			return nil
		}
	}
	return fmt.Errorf("%w: %s", ErrUnsafePath, target)
}

func resolveForCheck(path string) (string, error) {
	if _, err := os.Lstat(path); err == nil {
		return filepath.EvalSymlinks(path)
	} else if !errors.Is(err, os.ErrNotExist) {
		return "", err
	}
	parent := filepath.Dir(path)
	resolvedParent, err := filepath.EvalSymlinks(parent)
	if err != nil {
		return "", err
	}
	return filepath.Join(resolvedParent, filepath.Base(path)), nil
}

func SafeCleanupWorkspace(roots []string, target, runnerInstanceID string) error {
	if runnerInstanceID == "" {
		return fmt.Errorf("%w: runner instance ID required", ErrUnsafePath)
	}
	if err := ValidateAllowlistedPath(roots, target); err != nil {
		return err
	}
	info, err := os.Lstat(target)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	if info.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("%w: target is symlink", ErrUnsafePath)
	}
	marker := filepath.Join(target, ".ci-scope-runner-instance")
	markerInfo, err := os.Lstat(marker)
	if err != nil {
		return fmt.Errorf("%w: ownership marker: %v", ErrUnsafePath, err)
	}
	if markerInfo.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("%w: ownership marker is symlink", ErrUnsafePath)
	}
	markerData, err := os.ReadFile(marker)
	if err != nil || strings.TrimSpace(string(markerData)) != runnerInstanceID {
		return fmt.Errorf("%w: ownership marker mismatch", ErrUnsafePath)
	}
	if err := filepath.WalkDir(target, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.Type()&os.ModeSymlink != 0 {
			return fmt.Errorf("%w: symlink in workspace %s", ErrUnsafePath, path)
		}
		return nil
	}); err != nil {
		return err
	}
	return os.RemoveAll(target)
}

func CreateOwnedWorkspace(roots []string, target, runnerInstanceID string) error {
	if runnerInstanceID == "" {
		return fmt.Errorf("%w: runner instance ID required", ErrUnsafePath)
	}
	if err := ValidateAllowlistedPath(roots, target); err != nil {
		return err
	}
	if err := os.MkdirAll(target, 0700); err != nil {
		return err
	}
	info, err := os.Lstat(target)
	if err != nil || info.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("%w: workspace is symlink or unavailable", ErrUnsafePath)
	}
	return writeAtomic(filepath.Join(target, ".ci-scope-runner-instance"), []byte(runnerInstanceID+"\n"), 0600)
}
