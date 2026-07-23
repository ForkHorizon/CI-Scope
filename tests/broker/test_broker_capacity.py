from backend_broker_testkit import load_broker


def test_tick_respects_machine_capacity_when_dispatching(monkeypatch):
    broker = load_broker()
    calls, started = [], []

    def read_state():
        return {
            "version": 1,
            "actives": [],
            "queue": [
                {
                    "id": "job_1",
                    "repositorySlug": "test/repo",
                    "createdAt": "2023-01-01T10:00:00Z",
                },
                {
                    "id": "job_2",
                    "repositorySlug": "test/repo",
                    "createdAt": "2023-01-01T10:01:00Z",
                },
            ],
            "repos": [],
            "retries": {},
            "webhook": {},
        }

    monkeypatch.setattr(broker, "MACHINE_CAPACITY", 1)
    monkeypatch.setattr(broker, "MAX_CONCURRENT_JOBS", 2)
    monkeypatch.setattr(broker, "read_state", read_state)
    monkeypatch.setattr(broker, "write_state", calls.append)
    monkeypatch.setattr(
        broker,
        "start_runner",
        lambda job: started.append(job["id"]) or type("P", (), {"pid": 9000})(),
    )
    monkeypatch.setattr(broker, "now", lambda: "2023-01-01T00:00:00Z")

    broker.tick(polled=None, profiles=[])

    assert started == ["job_1"]
    assert [job["id"] for job in calls[-1]["queue"]] == ["job_2"]


def test_cleanup_stale_runners_only_removes_offline_runners(monkeypatch):
    broker, removed = load_broker(), []
    monkeypatch.setattr(
        broker,
        "list_repo_runners",
        lambda _slug: [
            {"id": 1, "name": "ci-scope-123-1", "busy": False, "status": "online"},
            {"id": 2, "name": "ci-scope-123-2", "busy": False, "status": "offline"},
        ],
    )
    monkeypatch.setattr(
        broker, "gh_json", lambda path, method: removed.append((path, method))
    )

    broker.cleanup_stale_runners({"repositorySlug": "test/repo", "jobId": "123"})

    assert removed == [("repos/test/repo/actions/runners/2", "DELETE")]
