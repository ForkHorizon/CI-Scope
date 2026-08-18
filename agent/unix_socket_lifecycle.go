package agent

import (
	"context"
	"errors"
	"fmt"
	"net"
	"os"
	"syscall"
	"time"
)

func (r *UnixSocketRuntime) Start(ctx context.Context) error {
	if r == nil {
		return ErrRuntimeNotStarted
	}
	r.mu.Lock()
	if r.started {
		r.mu.Unlock()
		return errors.New("agent runtime is already started")
	}
	listener, err := listenUnixSocket(r.config.Path, r.config.ExpectedPeerUID)
	if err != nil {
		r.mu.Unlock()
		return fmt.Errorf("listen on agent socket: %w", err)
	}
	if err := os.Chmod(r.config.Path, 0o600); err != nil {
		_ = listener.Close()
		r.mu.Unlock()
		return fmt.Errorf("secure agent socket: %w", err)
	}
	info, err := os.Lstat(r.config.Path)
	if err != nil || info.Mode()&os.ModeSocket == 0 {
		_ = listener.Close()
		r.mu.Unlock()
		if err != nil {
			return fmt.Errorf("stat agent socket: %w", err)
		}
		return errors.New("agent socket is not a Unix socket")
	}
	ownerUID, err := socketOwnerUID(info)
	if err != nil || ownerUID != r.config.ExpectedPeerUID {
		_ = listener.Close()
		r.mu.Unlock()
		if err != nil {
			return fmt.Errorf("read agent socket owner: %w", err)
		}
		return errors.New("agent socket has an unexpected owner")
	}
	if ctx == nil {
		ctx = context.Background()
	}
	r.ctx, r.cancel = context.WithCancel(ctx)
	r.listener = listener
	r.started = true
	r.wg.Add(2)
	go r.ownerLoop()
	go r.acceptLoop()
	r.mu.Unlock()
	return nil
}

// listenUnixSocket recovers only an owned socket path that no process is
// listening on. launchd can terminate the Agent without giving Close time to
// unlink the socket; leaving that inode behind would otherwise create a
// permanent restart loop. A successful dial proves that another listener owns
// the path, so it is never removed in that case.

func listenUnixSocket(path string, expectedUID uint32) (net.Listener, error) {
	listener, err := net.Listen("unix", path)
	if err == nil || !errors.Is(err, syscall.EADDRINUSE) {
		return listener, err
	}

	probe, probeErr := net.DialTimeout("unix", path, 100*time.Millisecond)
	if probeErr == nil {
		_ = probe.Close()
		return nil, err
	}
	info, statErr := os.Lstat(path)
	if statErr != nil || info.Mode()&os.ModeSocket == 0 {
		return nil, err
	}
	ownerUID, ownerErr := socketOwnerUID(info)
	if ownerErr != nil || ownerUID != expectedUID {
		return nil, err
	}
	if removeErr := os.Remove(path); removeErr != nil && !errors.Is(removeErr, os.ErrNotExist) {
		return nil, err
	}
	return net.Listen("unix", path)
}

func (r *UnixSocketRuntime) ownerLoop() {
	defer r.wg.Done()
	_ = r.owner.Run(r.ctx)
}

func (r *UnixSocketRuntime) acceptLoop() {
	defer r.wg.Done()
	for {
		conn, err := r.listener.Accept()
		if err != nil {
			select {
			case <-r.ctx.Done():
				return
			default:
			}
			continue
		}
		r.wg.Add(1)
		go func() {
			defer r.wg.Done()
			r.handleConnection(conn)
		}()
	}
}

func (r *UnixSocketRuntime) Close() error {
	if r == nil {
		return nil
	}
	r.mu.Lock()
	if !r.started {
		r.mu.Unlock()
		return nil
	}
	r.mu.Unlock()
	var closeErr error
	r.closeOnce.Do(func() {
		r.mu.Lock()
		r.cancel()
		closeErr = r.listener.Close()
		path := r.config.Path
		r.mu.Unlock()
		r.wg.Wait()
		if info, err := os.Lstat(path); err == nil && info.Mode()&os.ModeSocket != 0 {
			if ownerUID, ownerErr := socketOwnerUID(info); ownerErr == nil && ownerUID == r.config.ExpectedPeerUID {
				if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) && closeErr == nil {
					closeErr = err
				}
			}
		}
	})
	return closeErr
}
