import pytest

from backend_broker_testkit import load_broker


def test_shutdown_kills_active_runners_when_quit_marker_present(tmp_path, monkeypatch):
    broker = load_broker()
    terminated, cleaned_up, removed_dirs, posted, written = [], [], [], [], []

    marker = tmp_path / "quit-requested"
    marker.write_text("1", encoding="utf-8")
    monkeypatch.setattr(broker, "QUIT_MARKER_PATH", marker)
    monkeypatch.setattr(
        broker,
        "read_state",
        lambda: {"actives": [{"id": "job_1", "pid": 4242, "repositorySlug": "test/repo"}]},
    )
    monkeypatch.setattr(broker, "write_state", written.append)
    monkeypatch.setattr(broker, "active_is_running", lambda active: True)
    monkeypatch.setattr(
        broker, "terminate_active_process", lambda active, reason="": terminated.append((active["id"], reason))
    )
    monkeypatch.setattr(broker, "cleanup_runner_by_name", lambda slug, name: cleaned_up.append(slug))
    monkeypatch.setattr(broker, "remove_runner_dir", removed_dirs.append)
    monkeypatch.setattr(
        broker, "server_post_status", lambda job, status, error=None: posted.append((job["id"], status))
    )

    with pytest.raises(SystemExit):
        broker.shutdown()

    assert terminated == [("job_1", "app_quit")]
    assert cleaned_up == ["test/repo"]
    assert removed_dirs == ["job_1"]
    assert posted == [("job_1", "released")]
    assert written[-1]["actives"] == []
    assert not marker.exists()


def test_shutdown_leaves_active_runners_alone_without_quit_marker(tmp_path, monkeypatch):
    broker = load_broker()
    terminated = []

    monkeypatch.setattr(broker, "QUIT_MARKER_PATH", tmp_path / "quit-requested")
    monkeypatch.setattr(broker, "terminate_active_process", lambda active, reason="": terminated.append(active))

    with pytest.raises(SystemExit):
        broker.shutdown()

    assert terminated == []


def test_owner_app_alive_true_when_no_owner_pid_configured(monkeypatch):
    broker = load_broker()
    monkeypatch.setattr(broker, "OWNER_PID", 0)
    assert broker.owner_app_alive() is True


def test_owner_app_alive_reflects_process_alive(monkeypatch):
    broker = load_broker()
    monkeypatch.setattr(broker, "OWNER_PID", 4242)
    monkeypatch.setattr(broker, "process_alive", lambda pid: pid == 4242)
    assert broker.owner_app_alive() is True

    monkeypatch.setattr(broker, "process_alive", lambda pid: False)
    assert broker.owner_app_alive() is False


def test_shutdown_for_owner_exit_kills_runners_and_boots_self_out(monkeypatch):
    broker = load_broker()
    terminated, run_calls = [], []

    monkeypatch.setattr(broker, "OWNER_PID", 4242)
    monkeypatch.setattr(
        broker,
        "read_state",
        lambda: {"actives": [{"id": "job_1", "pid": 9000, "repositorySlug": "test/repo"}]},
    )
    monkeypatch.setattr(broker, "write_state", lambda state: None)
    monkeypatch.setattr(broker, "active_is_running", lambda active: True)
    monkeypatch.setattr(
        broker, "terminate_active_process", lambda active, reason="": terminated.append((active["id"], reason))
    )
    monkeypatch.setattr(broker, "cleanup_runner_by_name", lambda slug, name: None)
    monkeypatch.setattr(broker, "remove_runner_dir", lambda job_id: None)
    monkeypatch.setattr(broker, "server_post_status", lambda job, status, error=None: None)
    monkeypatch.setattr(broker.subprocess, "run", lambda *args, **kwargs: run_calls.append(args))

    with pytest.raises(SystemExit):
        broker.shutdown_for_owner_exit()

    assert terminated == [("job_1", "app_gone")]
    assert run_calls and "bootout" in run_calls[0][0]
