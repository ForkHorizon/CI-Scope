package agent

import "encoding/json"

type SchedulerReservation struct {
	ReservationID    string `json:"reservationId"`
	ReservationToken string `json:"reservationToken"`
	// The server historically exposed this as an epoch number on dispatch
	// responses and the scheduler alias exposes an RFC3339 string. Keep the
	// value opaque: it is server-owned and is only echoed during reconciliation.
	ExpiresAt   any                        `json:"expiresAt"`
	Executable  string                     `json:"executable,omitempty"`
	Workspace   string                     `json:"workspace,omitempty"`
	Correlation SchedulerRunnerCorrelation `json:"runnerCorrelation"`
}

type SchedulerClaimResponse struct {
	Claimed     bool                 `json:"claimed"`
	Reservation SchedulerReservation `json:"reservation"`
}

// Unmarshal both the scheduler alias and the original dispatch contract. The
// two endpoints intentionally remain wire-compatible while the Agent rolls
// forward independently from the Worker.

func (r *SchedulerClaimResponse) UnmarshalJSON(data []byte) error {
	var value struct {
		Claimed     bool                 `json:"claimed"`
		Reservation SchedulerReservation `json:"reservation"`
		Dispatch    *struct {
			Status            string                     `json:"status"`
			GithubJobKey      string                     `json:"githubJobKey"`
			RunAttempt        int64                      `json:"runAttempt"`
			ReservationID     string                     `json:"reservationId"`
			ExpiresAt         any                        `json:"expiresAt"`
			RunnerCorrelation SchedulerRunnerCorrelation `json:"runnerCorrelation"`
		} `json:"dispatch"`
	}
	if err := json.Unmarshal(data, &value); err != nil {
		return err
	}
	*r = SchedulerClaimResponse{Claimed: value.Claimed, Reservation: value.Reservation}
	if value.Dispatch != nil && value.Dispatch.ReservationID != "" {
		r.Claimed = value.Dispatch.Status == "claimed" || value.Dispatch.Status == "assigned"
		r.Reservation = SchedulerReservation{
			ReservationID:    value.Dispatch.ReservationID,
			ExpiresAt:        value.Dispatch.ExpiresAt,
			Correlation:      value.Dispatch.RunnerCorrelation,
			ReservationToken: value.Dispatch.RunnerCorrelation.ReservationToken,
		}
	}
	return nil
}
