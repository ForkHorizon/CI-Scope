// Tests that jobs running at once never share the ci-gates checkout or one repository's checkout.
package agent

import (
	"context"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestRunnerKeepsParallelJobsOffSharedCheckouts(t *testing.T) {
	var mu sync.Mutex
	active := map[string]int{}
	overlaps := []string{}
	runner := NewGateScriptRunner(t.TempDir(), "/gates", gatePin)
	runner.now = func() time.Time { return time.UnixMilli(42) }
	runner.run = func(_ context.Context, dir, name string, args ...string) ([]byte, error) {
		mu.Lock()
		active[dir]++
		if active[dir] > 1 {
			overlaps = append(overlaps, dir)
		}
		mu.Unlock()
		time.Sleep(2 * time.Millisecond)
		mu.Lock()
		active[dir]--
		mu.Unlock()
		switch line := name + " " + strings.Join(args, " "); {
		case line == "git rev-parse HEAD":
			return []byte(gatePin + "\n"), nil
		case name == "python3":
			return []byte(passingOutput), nil
		}
		return nil, nil
	}
	var jobs sync.WaitGroup
	for i, repository := range []string{"ForkHorizon/Example", "ForkHorizon/Example", "ForkHorizon/Other", "ForkHorizon/Other"} {
		job := gateJob()
		job.ID, job.Repository = "job-"+string(rune('a'+i)), repository
		jobs.Go(func() {
			if report, err := runner.Run(context.Background(), job); err != nil || report.Status != "passed" {
				t.Errorf("%s: %v %+v", job.ID, err, report)
			}
		})
	}
	jobs.Wait()
	if len(overlaps) > 0 {
		t.Fatalf("parallel jobs used one checkout at the same time: %v", overlaps)
	}
}
