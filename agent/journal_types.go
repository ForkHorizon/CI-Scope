package agent

import (
	"os"
	"sync"
	"time"
)

type Intent struct {
	ID               string            `json:"id"`
	OperationID      string            `json:"operationId"`
	Kind             IntentKind        `json:"kind"`
	Status           IntentStatus      `json:"status"`
	LocalEpoch       uint64            `json:"localEpoch"`
	RunnerInstanceID string            `json:"runnerInstanceId,omitempty"`
	PayloadHash      string            `json:"payloadHash,omitempty"`
	Payload          map[string]string `json:"payload,omitempty"`
	CreatedAt        time.Time         `json:"createdAt"`
}

type IntentJournal struct {
	mu   sync.Mutex
	file *os.File
}
