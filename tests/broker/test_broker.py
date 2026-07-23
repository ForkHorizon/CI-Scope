import sys
import os
from pathlib import Path
import importlib.machinery
import importlib.util
import time
import hmac
import hashlib

# Need to import CI Scope Broker but it has spaces and no .py extension.
broker_dir = Path(__file__).parent.parent.parent / "CI Scope" / "Broker"
sys.path.insert(0, str(broker_dir))

loader = importlib.machinery.SourceFileLoader("broker", str(broker_dir / "CI Scope Broker"))
spec = importlib.util.spec_from_loader("broker", loader)
broker = importlib.util.module_from_spec(spec)
loader.exec_module(broker)


def test_imports():
    assert broker.merge_jobs is not None


def test_prune_webhook_queued():
    broker.WEBHOOK_QUEUED_AT.clear()
    now = time.monotonic()

    # Add a job that is fresh
    broker.WEBHOOK_QUEUED_AT["job_1"] = now
    # Add a job that is old
    broker.WEBHOOK_QUEUED_AT["job_2"] = now - broker.WEBHOOK_QUEUE_GRACE_SECONDS - 10

    broker.prune_webhook_queued()

    assert "job_1" in broker.WEBHOOK_QUEUED_AT
    assert "job_2" not in broker.WEBHOOK_QUEUED_AT


def test_verify_signature():
    secret = "my-secret"
    body = b'{"hello": "world"}'

    # Valid signature
    digest = hmac.new(secret.encode("utf-8"), body, hashlib.sha256).hexdigest()
    valid_signature = f"sha256={digest}"
    assert broker.verify_signature(body, valid_signature, secret) is True

    # Invalid signature (wrong secret)
    wrong_digest = hmac.new(b"wrong-secret", body, hashlib.sha256).hexdigest()
    wrong_signature = f"sha256={wrong_digest}"
    assert broker.verify_signature(body, wrong_signature, secret) is False

    # Replay (or wrong body)
    wrong_body = b'{"hello": "there"}'
    assert broker.verify_signature(wrong_body, valid_signature, secret) is False

    # Malformed
    assert broker.verify_signature(body, "malformed", secret) is False


def test_merge_jobs():
    existing = [
        {"id": "job_1", "createdAt": "2023-01-01T10:00:00Z"},
        {"id": "job_2", "createdAt": "2023-01-01T10:05:00Z"},
    ]
    incoming = [
        {"id": "job_1", "createdAt": "2023-01-01T10:00:00Z", "updated": True},
        {"id": "job_3", "createdAt": "2023-01-01T10:02:00Z"},
    ]

    merged = broker.merge_jobs(existing, incoming)
    assert len(merged) == 3
    # Order should be by createdAt
    assert merged[0]["id"] == "job_1"
    assert merged[0].get("updated") is True  # incoming overwrites existing
    assert merged[1]["id"] == "job_3"
    assert merged[2]["id"] == "job_2"


def test_prune_retries():
    broker.RETRY_BUMPED_AT.clear()
    retries = {"job_1": 1, "job_2": 2, "job_3": 3}

    broker.RETRY_BUMPED_AT["job_1"] = 100
    broker.RETRY_BUMPED_AT["job_2"] = 100
    broker.RETRY_BUMPED_AT["job_3"] = 100

    queue = [{"id": "job_1"}]
    actives = [{"id": "job_2"}]

    pruned = broker.prune_retries(retries, queue, actives)

    assert "job_1" in pruned
    assert "job_2" in pruned
    assert "job_3" not in pruned

    assert "job_1" in broker.RETRY_BUMPED_AT
    assert "job_2" in broker.RETRY_BUMPED_AT
    assert "job_3" not in broker.RETRY_BUMPED_AT


def test_save_state(monkeypatch):
    calls = []

    def mock_write_state(state):
        calls.append(state)

    monkeypatch.setattr(broker, "write_state", mock_write_state)
    monkeypatch.setattr(broker, "now", lambda: "2023-01-01T00:00:00Z")
    monkeypatch.setattr(os, "getpid", lambda: 1234)

    queue = [
        {"id": "job_1"},
        {"id": "job_2"},  # job_2 will be in active, so should be removed
    ]
    actives = [{"id": "job_2"}]
    statuses = []
    error = None
    retries = {}
    profiles = []
    webhook = {}

    state = broker.save_state(actives, queue, statuses, error, retries, profiles, webhook)

    assert len(state["queue"]) == 1
    assert state["queue"][0]["id"] == "job_1"
    assert state["actives"] == actives
    assert state["active"] == actives[0]

    assert len(calls) == 1
    assert calls[0] == state


def test_queue_dedup_sort():
    # queue dedup/sort logic is tested implicitly in `test_merge_jobs`,
    # but we can explicitly test that queue deduplicates correctly
    existing = [
        {"id": "job_1", "createdAt": "2023-01-01T10:00:00Z", "val": 1},
        {"id": "job_2", "createdAt": "2023-01-01T10:05:00Z", "val": 2},
    ]
    incoming = [
        {"id": "job_1", "createdAt": "2023-01-01T10:00:00Z", "val": 3},
        {"id": "job_3", "createdAt": "2023-01-01T10:02:00Z", "val": 4},
    ]
    merged = broker.merge_jobs(existing, incoming)

    assert len(merged) == 3
    # Check deduplication uses incoming value
    job_1 = next(j for j in merged if j["id"] == "job_1")
    assert job_1["val"] == 3

    # Check sorting
    assert merged[0]["id"] == "job_1"
    assert merged[1]["id"] == "job_3"
    assert merged[2]["id"] == "job_2"


def test_queue_active_save_state_transitions(monkeypatch):
    calls = []

    def mock_write_state(state):
        calls.append(state)

    def mock_read_state():
        return {
            "version": 1,
            "actives": [],
            "queue": [
                {
                    "id": "job_1",
                    "repositorySlug": "test/repo",
                    "createdAt": "2023-01-01T10:00:00Z",
                    "labels": [],
                }
            ],
            "repos": [],
            "retries": {},
            "webhook": {},
        }

    class MockProcess:
        def __init__(self):
            self.pid = 9999

    def mock_start_runner(job):
        return MockProcess()

    monkeypatch.setattr(broker, "write_state", mock_write_state)
    monkeypatch.setattr(broker, "read_state", mock_read_state)
    monkeypatch.setattr(broker, "now", lambda: "2023-01-01T00:00:00Z")
    monkeypatch.setattr(broker, "start_runner", mock_start_runner)
    monkeypatch.setattr(time, "time", lambda: 1600000000.0)

    # We call tick with no new polled items
    broker.tick(polled=None, profiles=[])

    assert len(calls) > 0
    final_state = calls[-1]

    # job_1 should transition from queue to actives
    assert len(final_state["queue"]) == 0
    assert len(final_state["actives"]) == 1
    assert final_state["actives"][0]["id"] == "job_1"
    assert final_state["actives"][0]["status"] == "in_progress"


def test_read_last_progress_marker(tmp_path, monkeypatch):
    monkeypatch.setattr(broker, "LOG_DIR", tmp_path)
    log_path = tmp_path / f"{broker.safe_name('job_1')}.log"
    log_path.write_text(
        "Compiling...\n"
        '::ci-scope-progress:: {"step": "lint", "current": 1, "total": 20, "detail": "a.py"}\n'
        "some other line\n"
        '::ci-scope-progress:: {"step": "lint", "current": 2, "total": 20, "detail": "b.py"}\n'
    )

    marker = broker.read_last_progress_marker("job_1")
    assert marker == {"step": "lint", "current": 2, "total": 20, "detail": "b.py"}

    # No log file at all -> None, not an exception
    assert broker.read_last_progress_marker("missing-job") is None


def test_tick_attaches_progress_marker(monkeypatch):
    # Guards against the fresh-rebuild pitfall in tick(): final_actives is
    # rebuilt from a fresh re-read of state rather than from the `surviving`
    # list mutated in the first loop, so progress must be merged back in at
    # that rebuild step or it silently never reaches broker-state.json.
    calls = []
    state = {
        "version": 1,
        "actives": [
            {
                "id": "job_1",
                "repositorySlug": "test/repo",
                "createdAt": "2023-01-01T10:00:00Z",
                "labels": [],
                "pid": 4242,
                "status": "in_progress",
            }
        ],
        "queue": [],
        "repos": [],
        "retries": {},
        "webhook": {},
    }

    monkeypatch.setattr(broker, "write_state", calls.append)
    monkeypatch.setattr(broker, "read_state", lambda: state)
    monkeypatch.setattr(broker, "now", lambda: "2023-01-01T00:00:00Z")
    monkeypatch.setattr(broker, "active_is_running", lambda active: True)
    monkeypatch.setattr(broker, "active_timed_out", lambda active: False)
    monkeypatch.setattr(broker, "active_idle_too_long", lambda active: False)
    monkeypatch.setattr(
        broker,
        "read_last_progress_marker",
        lambda job_id: {"step": "lint", "current": 3, "total": 20, "detail": "foo.py"},
    )

    broker.tick(polled=None, profiles=[])

    final_state = calls[-1]
    assert len(final_state["actives"]) == 1
    assert final_state["actives"][0]["progress"] == {
        "step": "lint",
        "current": 3,
        "total": 20,
        "detail": "foo.py",
    }
