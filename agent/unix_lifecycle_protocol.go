package agent

const (
	reservationPreparePathPrefix = "/api/ci/v2/reservations/"
	runnerInstancePathPrefix     = "/api/ci/v2/runner-instances/"
)

type runnerLifecyclePayload struct {
	Type              string         `json:"type"`
	RunnerInstanceID  string         `json:"runnerInstanceId"`
	RunnerCorrelation map[string]any `json:"runnerCorrelation"`
}

type reservationPreparePayload struct {
	Type              string         `json:"type"`
	ReservationID     string         `json:"reservationId"`
	RunnerCorrelation map[string]any `json:"runnerCorrelation"`
}
