import importlib.machinery
import importlib.util
import time
import unittest
from pathlib import Path


BROKER_PATH = Path(__file__).resolve().parents[2] / "CI Scope" / "Broker" / "CI Scope Broker"


def load_broker():
    loader = importlib.machinery.SourceFileLoader("broker_unittest", str(BROKER_PATH))
    spec = importlib.util.spec_from_loader("broker_unittest", loader)
    broker = importlib.util.module_from_spec(spec)
    loader.exec_module(broker)
    return broker


class BrokerBackendTests(unittest.TestCase):
    def setUp(self):
        self.broker = load_broker()

    def test_poll_interval_is_slow_by_default(self):
        self.assertGreaterEqual(self.broker.poll_interval({"webhook": {}}), 900)

    def test_backend_snapshot_converts_to_broker_queue(self):
        payload = {
            "repositories": [{"slug": "ForkHorizon/Widget"}],
            "jobs": [
                {
                    "id": 2002,
                    "runId": 1001,
                    "repositorySlug": "ForkHorizon/Widget",
                    "workflowName": "CI",
                    "title": "Run tests",
                    "jobName": "quality",
                    "headBranch": "feature/events",
                    "status": "queued",
                    "url": "https://github.com/ForkHorizon/Widget/actions/runs/1001/job/2002",
                    "createdAt": "2026-06-15T10:00:01Z",
                    "labels": ["self-hosted", "macOS", "ARM64", "ci-scope-broker"],
                }
            ],
        }

        queue, statuses = self.broker.backend_snapshot_to_polled(
            payload,
            {"repos": [], "profiles": self.broker.DEFAULT_PROFILES},
            self.broker.DEFAULT_PROFILES,
        )

        self.assertEqual(queue[0]["id"], "ForkHorizon/Widget:1001:2002")
        self.assertEqual(queue[0]["profileId"], "forkhorizon-organization-broker")
        self.assertTrue(
            any(status["slug"] == "ForkHorizon/Widget" and status["queuedCount"] == 1 for status in statuses)
        )

    def test_tick_dispatches_backend_fed_queue_without_polling_github(self):
        queue = [
            {
                "id": "ForkHorizon/Widget:1001:2002",
                "repositorySlug": "ForkHorizon/Widget",
                "workflowName": "CI",
                "title": "Run tests",
                "jobName": "quality",
                "headBranch": "feature/events",
                "status": "queued",
                "url": "https://github.com/ForkHorizon/Widget/actions/runs/1001/job/2002",
                "createdAt": "2026-06-15T10:00:01Z",
                "labels": ["self-hosted", "macOS", "ARM64", "ci-scope-broker"],
                "runId": 1001,
                "jobId": 2002,
            }
        ]
        calls = []

        class MockProcess:
            pid = 9999

        def mock_read_state():
            return {
                "version": 1,
                "actives": [],
                "queue": queue,
                "repos": [],
                "retries": {},
                "webhook": {},
            }

        original_write_state = self.broker.write_state
        original_read_state = self.broker.read_state
        original_start_runner = self.broker.start_runner
        original_queued_jobs = self.broker.queued_jobs
        original_time = time.time
        try:
            self.broker.write_state = calls.append
            self.broker.read_state = mock_read_state
            self.broker.start_runner = lambda job: MockProcess()
            self.broker.queued_jobs = lambda *_: self.fail("queued_jobs should not be called")
            time.time = lambda: 1600000000.0
            self.broker.tick(polled=None, profiles=self.broker.DEFAULT_PROFILES)
        finally:
            self.broker.write_state = original_write_state
            self.broker.read_state = original_read_state
            self.broker.start_runner = original_start_runner
            self.broker.queued_jobs = original_queued_jobs
            time.time = original_time

        self.assertEqual(calls[-1]["queue"], [])
        self.assertEqual(calls[-1]["actives"][0]["id"], "ForkHorizon/Widget:1001:2002")


if __name__ == "__main__":
    unittest.main()

