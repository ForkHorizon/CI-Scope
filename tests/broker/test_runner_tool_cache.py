import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from backend_broker_testkit import load_broker


def test_start_runner_uses_writable_scope_tool_cache(tmp_path, monkeypatch):
    broker, captured = load_broker(), {}

    class MockProcess:
        pid = 1234

    monkeypatch.setattr(broker, "generate_jit_config", lambda _job: "jit-config")
    monkeypatch.setattr(broker, "prepare_runner_dir", lambda _job: tmp_path)
    monkeypatch.setattr(broker, "LOG_DIR", tmp_path)
    monkeypatch.setattr(broker, "TOOL_CACHE_DIR", tmp_path / "toolcache")
    monkeypatch.setattr(
        broker.subprocess,
        "Popen",
        lambda *_args, **kwargs: captured.update(kwargs) or MockProcess(),
    )

    broker.start_runner({"id": "job_1", "repositorySlug": "test/repo"})

    assert captured["env"]["RUNNER_TOOL_CACHE"] == str(tmp_path / "toolcache")
