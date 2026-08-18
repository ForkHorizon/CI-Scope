package agent

import "encoding/json"

type SchedulerRunnerCorrelation struct {
	RunnerInstanceID string `json:"runnerInstanceId"`
	RunnerName       string `json:"runnerName"`
	RunnerGroupID    int64  `json:"runnerGroupId"`
	OrganizationID   int64  `json:"organizationId"`
	InstallationID   int64  `json:"installationId"`
	PreparationID    string `json:"preparationId"`
	RunnerAttempt    int64  `json:"runnerAttempt"`
	ReservationToken string `json:"reservationToken"`
	GitHubJobKey     string `json:"githubJobKey,omitempty"`
	RunAttempt       int64  `json:"runAttempt,omitempty"`
}

// The Web contract distinguishes an unbound job from an omitted field. Keep
// the ergonomic zero values in Go, but always serialize the optional pair as
// explicit nulls until a GitHub job binds the runner.

func (c SchedulerRunnerCorrelation) MarshalJSON() ([]byte, error) {
	type wire struct {
		RunnerInstanceID string  `json:"runnerInstanceId"`
		RunnerName       string  `json:"runnerName"`
		RunnerGroupID    int64   `json:"runnerGroupId"`
		OrganizationID   int64   `json:"organizationId"`
		InstallationID   int64   `json:"installationId"`
		PreparationID    string  `json:"preparationId"`
		RunnerAttempt    int64   `json:"runnerAttempt"`
		ReservationToken string  `json:"reservationToken"`
		GitHubJobKey     *string `json:"githubJobKey"`
		RunAttempt       *int64  `json:"runAttempt"`
	}
	var githubJobKey *string
	if c.GitHubJobKey != "" {
		value := c.GitHubJobKey
		githubJobKey = &value
	}
	var runAttempt *int64
	if c.RunAttempt != 0 {
		value := c.RunAttempt
		runAttempt = &value
	}
	return json.Marshal(wire{
		RunnerInstanceID: c.RunnerInstanceID,
		RunnerName:       c.RunnerName,
		RunnerGroupID:    c.RunnerGroupID,
		OrganizationID:   c.OrganizationID,
		InstallationID:   c.InstallationID,
		PreparationID:    c.PreparationID,
		RunnerAttempt:    c.RunnerAttempt,
		ReservationToken: c.ReservationToken,
		GitHubJobKey:     githubJobKey,
		RunAttempt:       runAttempt,
	})
}
