import importlib.machinery
import importlib.util
import unittest
from pathlib import Path
from unittest.mock import patch


BROKER_PATH = (
    Path(__file__).resolve().parents[2] / "CI Scope" / "Broker" / "CI Scope Broker"
)
ACTIVE_JOB = {
    "id": "ForkHorizon/NexusUnity:1001:2002",
    "repositorySlug": "ForkHorizon/NexusUnity",
    "runId": 1001,
    "jobId": 2002,
    "pid": None,
}


def load_broker():
    loader = importlib.machinery.SourceFileLoader(
        "broker_finish_active", str(BROKER_PATH)
    )
    spec = importlib.util.spec_from_loader("broker_finish_active", loader)
    broker = importlib.util.module_from_spec(spec)
    loader.exec_module(broker)
    return broker


class FinishActiveTests(unittest.TestCase):
    """GitHub hands a connecting JIT runner ANY queued job whose labels match,
    not necessarily the one the broker leased — so a clean runner exit does not
    mean our job ran (NexusUnity PR #145, 2026-07-04). finish_active must check
    GitHub directly and only ever release (never self-report a terminal
    status); the workflow_job webhook is the sole source of a job actually
    completing.
    """

    def setUp(self):
        self.broker = load_broker()

    def run_finish_active(self, remote_status):
        status_calls = []
        with (
            patch.object(
                self.broker,
                "job_remote_status",
                lambda _a: {"status": remote_status, "lastError": None},
            ),
            patch.object(
                self.broker,
                "server_post_status",
                lambda job, status, error=None: status_calls.append(status),
            ),
            patch.object(self.broker, "cleanup_runner_by_name", lambda *_: None),
            patch.object(self.broker, "remove_runner_dir", lambda *_: None),
        ):
            retries = self.broker.finish_active(dict(ACTIVE_JOB), {})[0]
        return retries, status_calls

    def test_releases_lease_when_github_never_ran_the_leased_job(self):
        retries, status_calls = self.run_finish_active(remote_status="queued")
        self.assertEqual(status_calls, ["released"])
        self.assertEqual(retries.get(ACTIVE_JOB["id"]), 1)

    def test_does_not_self_report_when_job_actually_ran(self):
        retries, status_calls = self.run_finish_active(remote_status="completed")
        self.assertEqual(status_calls, [])
        self.assertNotIn(ACTIVE_JOB["id"], retries)


if __name__ == "__main__":
    unittest.main()
