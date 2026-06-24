import importlib.machinery
import importlib.util
import time
import unittest
from pathlib import Path
from unittest.mock import patch


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

    def test_server_claim_converts_worker_action_without_polling_github(self):
        calls = []

        def fake_post(path, payload):
            calls.append((path, payload))
            return {"action": dict(BACKEND_QUEUE_JOB)}

        with patch.object(self.broker, "BACKEND_URL", "https://ci.example.com"), \
             patch.object(self.broker, "server_post_json", fake_post), \
             patch.object(self.broker, "record_backend_status", lambda **_kwargs: None):
            queue, statuses = self.broker.server_claim_queue(
                {"repos": [], "profiles": self.broker.DEFAULT_PROFILES},
                self.broker.DEFAULT_PROFILES,
            )

        self.assertEqual(calls[0][0], "/api/ci/local/claim")
        self.assertEqual(queue[0]["id"], "ForkHorizon/Widget:1001:2002")
        self.assertTrue(any(status["queuedCount"] == 1 for status in statuses))

    def test_server_claim_releases_unmatched_action(self):
        calls = []
        action = dict(BACKEND_QUEUE_JOB, id="Other/Repo:1001:2002", repositorySlug="Other/Repo")

        def fake_post(path, payload):
            calls.append((path, payload))
            return {"action": action}

        with patch.object(self.broker, "BACKEND_URL", "https://ci.example.com"), \
             patch.object(self.broker, "SERVER_MODE", True), \
             patch.object(self.broker, "server_post_json", fake_post), \
             patch.object(self.broker, "record_backend_status", lambda **_kwargs: None):
            queue, statuses = self.broker.server_claim_queue(
                {"repos": [], "profiles": self.broker.DEFAULT_PROFILES},
                self.broker.DEFAULT_PROFILES,
            )

        self.assertEqual(queue, [])
        self.assertEqual(statuses, [])
        self.assertEqual(calls[1][0], "/api/ci/local/actions/Other%2FRepo%3A1001%3A2002/status")
        self.assertEqual(calls[1][1]["status"], "released")

    def test_server_heartbeat_reports_all_active_jobs(self):
        calls = []

        with patch.object(self.broker, "read_state", lambda: {"actives": [{"id": "a"}, {"id": "b"}]}), \
             patch.object(self.broker, "server_post_json", lambda path, payload: calls.append((path, payload)) or {"ok": True}), \
             patch.object(self.broker, "record_backend_status", lambda **_kwargs: None):
            self.broker.server_heartbeat()

        self.assertEqual(calls[0][0], "/api/ci/local/heartbeat")
        self.assertEqual(calls[0][1]["activeJobIds"], ["a", "b"])

    def test_tick_releases_server_claim_when_runner_start_fails(self):
        queue = [dict(BACKEND_QUEUE_JOB)]
        status_calls = []

        def mock_read_state():
            return {
                "version": 1,
                "actives": [],
                "queue": [],
                "repos": [],
                "retries": {},
                "webhook": {},
            }

        with patch.object(self.broker, "SERVER_MODE", True), \
             patch.object(self.broker, "read_state", mock_read_state), \
             patch.object(self.broker, "write_state", lambda _state: None), \
             patch.object(self.broker, "start_runner", lambda _job: (_ for _ in ()).throw(RuntimeError("boom"))), \
             patch.object(self.broker, "server_post_status", lambda job, status, error=None: status_calls.append((job, status, error))):
            self.broker.tick((queue, []), self.broker.DEFAULT_PROFILES)

        self.assertEqual(status_calls[0][1], "released")
        self.assertIn("boom", status_calls[0][2])

    def test_backend_request_sends_non_bot_user_agent(self):
        # Cloudflare BIC 403s the default Python-urllib UA before it reaches the
        # Worker, so every backend call must carry an overridable product UA.
        with patch.object(self.broker, "BACKEND_URL", "https://ci.example.com"), \
             patch.object(self.broker, "BACKEND_USER_AGENT", "CI-Scope-Broker/9.9"):
            request = self.broker.backend_request("/api/ci/local/heartbeat")

        ua = request.get_header("User-agent")
        self.assertEqual(ua, "CI-Scope-Broker/9.9")
        self.assertNotIn("urllib", (ua or "").lower())

    def _server_job(self, action, machine_labels):
        with patch.object(self.broker, "MACHINE_LABELS", machine_labels):
            return self.broker.server_job_payload(
                action, {"repos": [], "profiles": self.broker.DEFAULT_PROFILES}, self.broker.DEFAULT_PROFILES
            )

    def test_server_job_payload_accepts_managed_job_with_nonmatching_labels(self):
        # Server mode trusts the backend lease: a managed job whose runs-on differs
        # from the org/per-repo config is still accepted (runner uses the job's own
        # labels). moodling build-and-test would otherwise strand forever.
        job = self._server_job(
            dict(BACKEND_QUEUE_JOB, repositorySlug="ForkHorizon/moodling", labels=["self-hosted", "macOS", "ARM64", "moodling"]),
            ["self-hosted", "macOS", "ARM64", "ci-scope-broker", "moodling", "ollama"],
        )
        self.assertEqual(job["labels"], ["self-hosted", "macOS", "ARM64", "moodling"])

    def test_server_job_payload_rejects_unmanaged_repo(self):
        self.assertIsNone(self._server_job(
            dict(BACKEND_QUEUE_JOB, repositorySlug="Stranger/repo"), ["self-hosted", "macOS", "ARM64", "ci-scope-broker"]))

    def test_server_job_payload_rejects_job_machine_cannot_satisfy(self):
        self.assertIsNone(self._server_job(
            dict(BACKEND_QUEUE_JOB, repositorySlug="ForkHorizon/moodling", labels=["self-hosted", "macOS", "ARM64", "gpu"]),
            ["self-hosted", "macOS", "ARM64", "ci-scope-broker"]))

    def test_server_status_posts_to_worker_action_endpoint(self):
        calls = []

        with patch.object(self.broker, "BACKEND_URL", "https://ci.example.com"), \
             patch.object(self.broker, "SERVER_MODE", True), \
             patch.object(
                 self.broker,
                 "server_post_json",
                 lambda path, payload: calls.append((path, payload)) or {"ok": True},
             ):
            self.broker.server_post_status({"id": "ForkHorizon/Widget:1001:2002"}, "in_progress")

        self.assertEqual(calls[0][0], "/api/ci/local/actions/ForkHorizon%2FWidget%3A1001%3A2002/status")
        self.assertEqual(calls[0][1]["status"], "in_progress")


if __name__ == "__main__":
    unittest.main()
