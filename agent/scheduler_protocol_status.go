package agent

import "encoding/json"

type SchedulerReconcileResponse struct {
	State         string `json:"state"`
	JITConfig     string `json:"jitConfig,omitempty"`
	JITStatus     string `json:"jitStatus,omitempty"`
	Terminal      bool   `json:"terminal"`
	RunnerRemoved bool   `json:"runnerRemoved"`
}

type SchedulerStatusResponse struct {
	State         string `json:"state"`
	JobState      string `json:"jobState"`
	Terminal      bool   `json:"terminal"`
	RunnerRemoved bool   `json:"runnerRemoved"`
}

func (r *SchedulerStatusResponse) UnmarshalJSON(data []byte) error {
	var value struct {
		State         string `json:"state"`
		JobState      string `json:"jobState"`
		Terminal      bool   `json:"terminal"`
		RunnerRemoved bool   `json:"runnerRemoved"`
		Dispatch      *struct {
			Status       string `json:"status"`
			GithubJobKey string `json:"githubJobKey"`
			RunAttempt   int64  `json:"runAttempt"`
		} `json:"dispatch"`
	}
	if err := json.Unmarshal(data, &value); err != nil {
		return err
	}
	*r = SchedulerStatusResponse{
		State: value.State, JobState: value.JobState,
		Terminal: value.Terminal, RunnerRemoved: value.RunnerRemoved,
	}
	if value.Dispatch != nil {
		r.State = value.Dispatch.Status
		r.JobState = value.Dispatch.Status
		r.Terminal = value.Dispatch.Status == "terminal"
	}
	return nil
}
