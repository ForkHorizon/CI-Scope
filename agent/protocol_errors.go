package agent

type ServerProtocolError struct {
	Code         string `json:"code"`
	Message      string `json:"message"`
	RequestID    string `json:"requestId,omitempty"`
	RetryAfterMs uint64 `json:"retryAfterMs,omitempty"`
}
