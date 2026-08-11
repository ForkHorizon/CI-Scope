from test_broker import broker


def test_webhook_rebinds_active_runner_to_actual_github_job(monkeypatch):
    state = {
        "version": 1,
        "actives": [{"id": "leased-job", "runnerName": "runner-1", "pid": 4242}],
        "queue": [],
        "repos": [],
        "retries": {},
        "webhook": {},
    }
    saved = []
    actual = {
        "id": "actual-job",
        "repositorySlug": "ForkHorizon/Widget",
        "jobName": "Swift Compile Gate",
        "status": "in_progress",
        "runnerName": "runner-1",
    }

    monkeypatch.setattr(broker, "read_registry", lambda: {})
    monkeypatch.setattr(broker, "enabled_profiles", lambda _registry: [])
    monkeypatch.setattr(broker, "read_state", lambda: state)
    monkeypatch.setattr(broker, "webhook_job_payload", lambda *_args: (actual, {"id": "profile"}, [], None))
    monkeypatch.setattr(broker, "upsert_repo_status", lambda statuses, *_args: statuses)
    monkeypatch.setattr(broker, "save_state", lambda *args: saved.append(args))

    broker.apply_workflow_job_event({"action": "in_progress"}, "delivery-1")

    active = saved[-1][0][0]
    assert active["id"] == "actual-job"
    assert active["pid"] == 4242
    assert active["runnerName"] == "runner-1"
