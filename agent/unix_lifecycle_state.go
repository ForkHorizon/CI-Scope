package agent

import "time"

type reservationPrepareResponse struct {
	JITConfig        string `json:"jitConfig"`
	EncodedJITConfig string `json:"encoded_jit_config"`
	JITStatus        string `json:"jitStatus"`
}

type controlLease struct {
	appInstanceID string
	token         string
	expiresAt     time.Time
	drainDeadline time.Time
	draining      bool
}
