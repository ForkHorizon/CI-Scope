import sys
import plistlib
from pathlib import Path
import importlib.machinery
import importlib.util

# Need to import CI Scope Broker but it has spaces and no .py extension.
broker_dir = Path(__file__).parent.parent.parent / "CI Scope" / "Broker"
sys.path.insert(0, str(broker_dir))

loader = importlib.machinery.SourceFileLoader(
    "broker_cleanup", str(broker_dir / "CI Scope Broker")
)
spec = importlib.util.spec_from_loader("broker_cleanup", loader)
broker = importlib.util.module_from_spec(spec)
loader.exec_module(broker)


def test_remove_runner_dir_removes_matching_derived_data_but_keeps_unrelated(
    tmp_path, monkeypatch
):
    jobs_dir = tmp_path / "jobs"
    legacy_jobs_dir = tmp_path / "legacy-jobs"
    derived_data_dir = tmp_path / "DerivedData"
    runner_dir = jobs_dir / broker.safe_name("job_1")
    runner_dir.mkdir(parents=True)
    legacy_jobs_dir.mkdir()
    derived_data_dir.mkdir()

    def write_info(path, workspace):
        path.mkdir()
        with (path / "info.plist").open("wb") as handle:
            plistlib.dump({"WorkspacePath": str(workspace)}, handle)

    write_info(
        derived_data_dir / "job-cache", runner_dir / "_work" / "repo" / "App.xcodeproj"
    )
    write_info(
        derived_data_dir / "unrelated-cache", tmp_path / "other" / "App.xcodeproj"
    )
    monkeypatch.setattr(broker, "JOBS_DIR", jobs_dir)
    monkeypatch.setattr(broker, "LEGACY_JOBS_DIR", legacy_jobs_dir)
    monkeypatch.setattr(broker, "DERIVED_DATA_DIR", derived_data_dir)

    broker.remove_runner_dir("job_1")

    assert not runner_dir.exists()
    assert not (derived_data_dir / "job-cache").exists()
    assert (derived_data_dir / "unrelated-cache").exists()


def test_prune_orphan_job_dirs_cleans_legacy_jobs_and_orphan_derived_data(
    tmp_path, monkeypatch
):
    jobs_dir = tmp_path / "jobs"
    legacy_jobs_dir = tmp_path / "legacy-jobs"
    derived_data_dir = tmp_path / "DerivedData"
    active_dir = jobs_dir / broker.safe_name("active")
    orphan_dir = legacy_jobs_dir / broker.safe_name("orphan")
    active_dir.mkdir(parents=True)
    orphan_dir.mkdir(parents=True)
    derived_data_dir.mkdir()

    def write_info(path, workspace):
        path.mkdir()
        with (path / "info.plist").open("wb") as handle:
            plistlib.dump({"WorkspacePath": str(workspace)}, handle)

    write_info(derived_data_dir / "active-cache", active_dir / "App.xcodeproj")
    write_info(derived_data_dir / "orphan-cache", orphan_dir / "App.xcodeproj")
    monkeypatch.setattr(broker, "JOBS_DIR", jobs_dir)
    monkeypatch.setattr(broker, "LEGACY_JOBS_DIR", legacy_jobs_dir)
    monkeypatch.setattr(broker, "DERIVED_DATA_DIR", derived_data_dir)
    monkeypatch.setattr(broker, "read_state", lambda: {"actives": [{"id": "active"}]})

    broker.prune_orphan_job_dirs()
    broker.prune_orphan_derived_data()

    assert active_dir.exists()
    assert (derived_data_dir / "active-cache").exists()
    assert not orphan_dir.exists()
    assert not (derived_data_dir / "orphan-cache").exists()
