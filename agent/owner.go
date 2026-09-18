package agent

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

type OwnerLease struct {
	file            *os.File
	root            string
	agentInstanceID string
	epoch           uint64
	releaseOnce     sync.Once
	released        chan struct{}
}

func AcquireOwnerLock(root, agentInstanceID string) (*OwnerLease, error) {
	if agentInstanceID == "" {
		return nil, errors.New("agent instance ID is required")
	}
	if err := os.MkdirAll(root, 0700); err != nil {
		return nil, fmt.Errorf("create owner directory: %w", err)
	}
	lockPath := filepath.Join(root, "owner.lock")
	file, err := os.OpenFile(lockPath, os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return nil, fmt.Errorf("open owner lock: %w", err)
	}
	if err := file.Chmod(0600); err != nil {
		_ = file.Close()
		return nil, fmt.Errorf("secure owner lock: %w", err)
	}
	if err := syscall.Flock(int(file.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		_ = file.Close()
		return nil, fmt.Errorf("owner lock is held: %w", err)
	}
	epoch, err := nextEpoch(root)
	if err != nil {
		_ = syscall.Flock(int(file.Fd()), syscall.LOCK_UN)
		_ = file.Close()
		return nil, err
	}
	record := ownerRecord{AgentInstanceID: agentInstanceID, PID: os.Getpid(), AcquiredAt: time.Now().UTC(), LocalEpoch: epoch}
	if err := writeOwnerRecord(file, record); err != nil {
		_ = syscall.Flock(int(file.Fd()), syscall.LOCK_UN)
		_ = file.Close()
		return nil, err
	}
	return &OwnerLease{file: file, root: root, agentInstanceID: agentInstanceID, epoch: epoch, released: make(chan struct{})}, nil
}

func (l *OwnerLease) Token() FencingToken {
	return FencingToken{AgentInstanceID: l.agentInstanceID, LocalEpoch: l.epoch}
}

func (l *OwnerLease) Check(token FencingToken) error {
	if l == nil || token != l.Token() {
		return errors.New("fencing token mismatch")
	}
	select {
	case <-l.released:
		return errors.New("owner lease released")
	default:
	}
	current, err := readEpoch(filepath.Join(l.root, "owner.epoch"))
	if err != nil {
		return err
	}
	if current != l.epoch {
		return fmt.Errorf("stale local epoch %d, current %d", l.epoch, current)
	}
	return nil
}

func (l *OwnerLease) Release() error {
	if l == nil {
		return nil
	}
	var err error
	l.releaseOnce.Do(func() {
		close(l.released)
		err = syscall.Flock(int(l.file.Fd()), syscall.LOCK_UN)
		if closeErr := l.file.Close(); err == nil {
			err = closeErr
		}
	})
	return err
}

func nextEpoch(root string) (uint64, error) {
	path := filepath.Join(root, "owner.epoch")
	current, err := readEpoch(path)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return 0, err
	}
	if current == ^uint64(0) {
		return 0, errors.New("local epoch exhausted")
	}
	current++
	if err := writeAtomic(path, []byte(strconv.FormatUint(current, 10)+"\n"), 0600); err != nil {
		return 0, fmt.Errorf("persist local epoch: %w", err)
	}
	return current, nil
}

func readEpoch(path string) (uint64, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return 0, err
	}
	value, err := strconv.ParseUint(strings.TrimSpace(string(data)), 10, 64)
	if err != nil {
		return 0, fmt.Errorf("invalid epoch: %w", err)
	}
	return value, nil
}

func writeOwnerRecord(file *os.File, value any) error {
	data, err := json.Marshal(value)
	if err != nil {
		return err
	}
	if _, err := file.Seek(0, 0); err != nil {
		return err
	}
	if err := file.Truncate(0); err != nil {
		return err
	}
	if _, err := file.Write(append(data, '\n')); err != nil {
		return err
	}
	return file.Sync()
}

func writeAtomic(path string, data []byte, mode os.FileMode) error {
	tmp, err := os.CreateTemp(filepath.Dir(path), ".tmp-")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)
	if err := tmp.Chmod(mode); err != nil {
		_ = tmp.Close()
		return err
	}
	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Sync(); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Rename(tmpName, path); err != nil {
		return err
	}
	directory, err := os.Open(filepath.Dir(path))
	if err != nil {
		return err
	}
	defer directory.Close()
	return directory.Sync()
}
