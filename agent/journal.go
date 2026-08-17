package agent

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"sort"
	"time"
)

var ErrCorruptJournal = errors.New("corrupt intent journal")

// JSONL is deliberately the smallest stdlib-only durable format. It has no
// SQL transactions or indexes; migrate to SQLite when query volume or schema
// evolution requires them. Each record is append+fsync before returning.
func OpenIntentJournal(path string) (*IntentJournal, error) {
	file, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_RDWR, 0600)
	if err != nil {
		return nil, err
	}
	if err := file.Chmod(0600); err != nil {
		_ = file.Close()
		return nil, err
	}
	return &IntentJournal{file: file}, nil
}

func (j *IntentJournal) Close() error {
	if j == nil || j.file == nil {
		return nil
	}
	return j.file.Close()
}

func (j *IntentJournal) Append(intent Intent) error {
	if intent.ID == "" || intent.Kind == "" || intent.Status == "" {
		return errors.New("intent ID, kind and status are required")
	}
	if intent.CreatedAt.IsZero() {
		intent.CreatedAt = time.Now().UTC()
	}
	data, err := json.Marshal(intent)
	if err != nil {
		return err
	}
	j.mu.Lock()
	defer j.mu.Unlock()
	if _, err := j.file.Write(append(data, '\n')); err != nil {
		return err
	}
	return j.file.Sync()
}

func (j *IntentJournal) Pending() ([]Intent, error) {
	j.mu.Lock()
	defer j.mu.Unlock()
	if _, err := j.file.Seek(0, 0); err != nil {
		return nil, err
	}
	scanner := bufio.NewScanner(j.file)
	latest := make(map[string]Intent)
	for scanner.Scan() {
		var intent Intent
		if err := json.Unmarshal(scanner.Bytes(), &intent); err != nil {
			return nil, fmt.Errorf("%w: %v", ErrCorruptJournal, err)
		}
		if intent.ID == "" {
			return nil, fmt.Errorf("%w: missing intent ID", ErrCorruptJournal)
		}
		latest[intent.ID] = intent
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	if _, err := j.file.Seek(0, 2); err != nil {
		return nil, err
	}
	result := make([]Intent, 0, len(latest))
	for _, intent := range latest {
		if intent.Status != IntentAcknowledged {
			result = append(result, intent)
		}
	}
	sort.Slice(result, func(i, k int) bool { return result[i].ID < result[k].ID })
	return result, nil
}
