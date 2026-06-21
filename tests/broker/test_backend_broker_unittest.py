import importlib.machinery
import importlib.util
import time
import unittest
from pathlib import Path


BROKER_PATH = Path(__file__).resolve().parents[2] / "CI Scope" / "Broker" / "CI Scope Broker"
BACKEND_QUEUE_JOB = {
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


class MockProcess:
    pid = 9999


class StopLoop(Exception):
    pass


class FakeSSEResponse:
    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False

    def __iter__(self):
        return iter([
            b"id: 12\n",
            b"event: workflow_job\n",
            b"data: {}\n",
            b"\n",
        ])


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
        queue = [dict(BACKEND_QUEUE_JOB)]
        calls = []

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

    def test_backend_sse_event_wakes_snapshot_sync(self):
        syncs = []
        opened = []

        def fake_urlopen(_request, timeout):
            if not opened:
                opened.append(timeout)
                return FakeSSEResponse()
            raise RuntimeError("stop")

        original_urlopen = self.broker.urllib.request.urlopen
        original_sleep = self.broker.time.sleep
        original_backend_url = self.broker.BACKEND_URL
        original_last_event_id = self.broker.BACKEND_LAST_EVENT_ID
        original_record_status = self.broker.record_backend_status
        original_sync = self.broker.sync_backend_snapshot
        try:
            self.broker.BACKEND_URL = "https://backend.example.com"
            self.broker.BACKEND_LAST_EVENT_ID = 0
            self.broker.urllib.request.urlopen = fake_urlopen
            self.broker.record_backend_status = lambda **_kwargs: None
            self.broker.sync_backend_snapshot = lambda reason: syncs.append((reason, self.broker.BACKEND_LAST_EVENT_ID)) or True
            self.broker.time.sleep = lambda _seconds: (_ for _ in ()).throw(StopLoop())

            with self.assertRaises(StopLoop):
                self.broker.backend_stream_loop()
        finally:
            self.broker.urllib.request.urlopen = original_urlopen
            self.broker.time.sleep = original_sleep
            self.broker.BACKEND_URL = original_backend_url
            self.broker.BACKEND_LAST_EVENT_ID = original_last_event_id
            self.broker.record_backend_status = original_record_status
            self.broker.sync_backend_snapshot = original_sync

        self.assertEqual(syncs, [("sse", 12)])


if __name__ == "__main__":
    unittest.main()
