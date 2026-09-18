package agent

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	_ "github.com/mattn/go-sqlite3"
)

type SQLiteStore struct{ db *sql.DB }

func OpenSQLiteStore(path string) (*SQLiteStore, error) {
	db, err := sql.Open("sqlite3", path)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	store := &SQLiteStore{db: db}
	if err := store.migrate(context.Background()); err != nil {
		_ = db.Close()
		return nil, err
	}
	return store, nil
}

func (s *SQLiteStore) migrate(ctx context.Context) error {
	for _, statement := range []string{
		"PRAGMA journal_mode = WAL",
		"PRAGMA synchronous = FULL",
		"PRAGMA foreign_keys = ON",
		"PRAGMA busy_timeout = 5000",
		`CREATE TABLE IF NOT EXISTS agent_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)`,
		`CREATE TABLE IF NOT EXISTS intents (id TEXT PRIMARY KEY, operation_id TEXT NOT NULL, kind TEXT NOT NULL, status TEXT NOT NULL, local_epoch INTEGER NOT NULL, runner_instance_id TEXT NOT NULL DEFAULT '', payload_hash TEXT NOT NULL DEFAULT '', payload_json TEXT NOT NULL DEFAULT '{}', created_at TEXT NOT NULL)`,
		`CREATE INDEX IF NOT EXISTS intents_status_idx ON intents(status)`,
		`CREATE TABLE IF NOT EXISTS machine_state (machine_id TEXT PRIMARY KEY, boot_id TEXT NOT NULL, agent_instance_id TEXT NOT NULL, session_id TEXT, session_epoch INTEGER NOT NULL DEFAULT 0, server_revision INTEGER NOT NULL DEFAULT 0, local_owner_epoch INTEGER NOT NULL DEFAULT 0, control_lease_state TEXT NOT NULL DEFAULT 'inactive', updated_at TEXT NOT NULL)`,
		`CREATE TABLE IF NOT EXISTS runner_processes (runner_instance_id TEXT PRIMARY KEY, runner_id TEXT, runner_name TEXT NOT NULL, runner_attempt INTEGER NOT NULL DEFAULT 0, pid INTEGER, process_start_time INTEGER, process_group_id INTEGER, executable TEXT, workspace TEXT, session_epoch INTEGER NOT NULL, updated_at TEXT NOT NULL)`,
		`CREATE TABLE IF NOT EXISTS pending_requests (request_id TEXT PRIMARY KEY, payload_hash TEXT NOT NULL, session_epoch INTEGER NOT NULL, operation_id TEXT, outcome TEXT, response_json TEXT, updated_at TEXT NOT NULL)`,
	} {
		if _, err := s.db.ExecContext(ctx, statement); err != nil {
			return err
		}
	}
	return nil
}

func (s *SQLiteStore) Close() error {
	if s == nil || s.db == nil {
		return nil
	}
	return s.db.Close()
}

func (s *SQLiteStore) PutMetadata(ctx context.Context, key, value string) error {
	if key == "" {
		return errors.New("metadata key is required")
	}
	_, err := s.db.ExecContext(ctx, `INSERT INTO agent_metadata(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value`, key, value)
	return err
}

func (s *SQLiteStore) GetMetadata(ctx context.Context, key string) (string, error) {
	var value string
	err := s.db.QueryRowContext(ctx, `SELECT value FROM agent_metadata WHERE key = ?`, key).Scan(&value)
	return value, err
}

func (s *SQLiteStore) PutIntent(ctx context.Context, intent Intent) error {
	if intent.ID == "" || intent.OperationID == "" || intent.Kind == "" || intent.Status == "" {
		return errors.New("intent ID, operation ID, kind and status are required")
	}
	if intent.CreatedAt.IsZero() {
		intent.CreatedAt = time.Now().UTC()
	}
	payload, err := json.Marshal(intent.Payload)
	if err != nil {
		return err
	}
	_, err = s.db.ExecContext(ctx, `
		INSERT INTO intents(id, operation_id, kind, status, local_epoch, runner_instance_id, payload_hash, payload_json, created_at)
		VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(id) DO UPDATE SET operation_id=excluded.operation_id, kind=excluded.kind, status=excluded.status, local_epoch=excluded.local_epoch, runner_instance_id=excluded.runner_instance_id, payload_hash=excluded.payload_hash, payload_json=excluded.payload_json, created_at=excluded.created_at`,
		intent.ID, intent.OperationID, intent.Kind, intent.Status, intent.LocalEpoch, intent.RunnerInstanceID, intent.PayloadHash, string(payload), intent.CreatedAt.UTC().Format(time.RFC3339Nano))
	return err
}

func (s *SQLiteStore) PendingIntents(ctx context.Context) ([]Intent, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, operation_id, kind, status, local_epoch, runner_instance_id, payload_hash, payload_json, created_at FROM intents WHERE status != ? ORDER BY id`, IntentAcknowledged)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var result []Intent
	for rows.Next() {
		var intent Intent
		var kind, status, payloadJSON, createdAt string
		if err := rows.Scan(&intent.ID, &intent.OperationID, &kind, &status, &intent.LocalEpoch, &intent.RunnerInstanceID, &intent.PayloadHash, &payloadJSON, &createdAt); err != nil {
			return nil, err
		}
		intent.Kind, intent.Status = IntentKind(kind), IntentStatus(status)
		if err := json.Unmarshal([]byte(payloadJSON), &intent.Payload); err != nil {
			return nil, fmt.Errorf("decode intent %s: %w", intent.ID, err)
		}
		intent.CreatedAt, err = time.Parse(time.RFC3339Nano, createdAt)
		if err != nil {
			return nil, err
		}
		result = append(result, intent)
	}
	return result, rows.Err()
}
