PRAGMA journal_mode = WAL;
PRAGMA synchronous = FULL;
PRAGMA foreign_keys = ON;
PRAGMA busy_timeout = 5000;

CREATE TABLE IF NOT EXISTS agent_metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS intents (
    id TEXT PRIMARY KEY,
    operation_id TEXT NOT NULL,
    kind TEXT NOT NULL,
    status TEXT NOT NULL,
    local_epoch INTEGER NOT NULL,
    runner_instance_id TEXT NOT NULL DEFAULT '',
    payload_hash TEXT NOT NULL DEFAULT '',
    payload_json TEXT NOT NULL DEFAULT '{}',
    created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS intents_status_idx ON intents(status);

CREATE TABLE IF NOT EXISTS machine_state (
    machine_id TEXT PRIMARY KEY,
    boot_id TEXT NOT NULL,
    agent_instance_id TEXT NOT NULL,
    session_id TEXT,
    session_epoch INTEGER NOT NULL DEFAULT 0,
    server_revision INTEGER NOT NULL DEFAULT 0,
    local_owner_epoch INTEGER NOT NULL DEFAULT 0,
    control_lease_state TEXT NOT NULL DEFAULT 'inactive',
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS runner_processes (
    runner_instance_id TEXT PRIMARY KEY,
    runner_id TEXT,
    runner_name TEXT NOT NULL,
    runner_attempt INTEGER NOT NULL DEFAULT 0,
    pid INTEGER,
    process_start_time INTEGER,
    process_group_id INTEGER,
    executable TEXT,
    workspace TEXT,
    session_epoch INTEGER NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS pending_requests (
    request_id TEXT PRIMARY KEY,
    payload_hash TEXT NOT NULL,
    session_epoch INTEGER NOT NULL,
    operation_id TEXT,
    outcome TEXT,
    response_json TEXT,
    updated_at TEXT NOT NULL
);
