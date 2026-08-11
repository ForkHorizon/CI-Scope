import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))

from backend_broker_testkit import BACKEND_QUEUE_JOB, load_broker


class BrokerServerModeTests(unittest.TestCase):
    def setUp(self):
        self.broker = load_broker()

    def test_server_claim_converts_worker_action_without_polling_github(self):
        calls = []

        def fake_post(path, payload):
            calls.append((path, payload))
            return {"action": dict(BACKEND_QUEUE_JOB)}

        with (
            patch.object(self.broker, "BACKEND_URL", "https://ci.example.com"),
            patch.object(self.broker, "server_post_json", fake_post),
            patch.object(self.broker, "record_backend_status", lambda **_kwargs: None),
        ):
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

        with (
            patch.object(self.broker, "BACKEND_URL", "https://ci.example.com"),
            patch.object(self.broker, "SERVER_MODE", True),
            patch.object(self.broker, "server_post_json", fake_post),
            patch.object(self.broker, "record_backend_status", lambda **_kwargs: None),
        ):
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

        with (
            patch.object(self.broker, "read_state", lambda: {"actives": [{"id": "a"}, {"id": "b"}]}),
            patch.object(
                self.broker, "server_post_json", lambda path, payload: calls.append((path, payload)) or {"ok": True}
            ),
            patch.object(self.broker, "record_backend_status", lambda **_kwargs: None),
        ):
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

        with (
            patch.object(self.broker, "SERVER_MODE", True),
            patch.object(self.broker, "read_state", mock_read_state),
            patch.object(self.broker, "write_state", lambda _state: None),
            patch.object(self.broker, "start_runner", lambda _job: (_ for _ in ()).throw(RuntimeError("boom"))),
            patch.object(
                self.broker,
                "server_post_status",
                lambda job, status, error=None: status_calls.append((job, status, error)),
            ),
        ):
            self.broker.tick((queue, []), self.broker.DEFAULT_PROFILES)

        self.assertEqual(status_calls[0][1], "released")
        self.assertIn("boom", status_calls[0][2])

    def test_backend_request_sends_non_bot_user_agent(self):
        # Cloudflare BIC 403s the default Python-urllib UA before it reaches the
        # Worker, so every backend call must carry an overridable product UA.
        with (
            patch.object(self.broker, "BACKEND_URL", "https://ci.example.com"),
            patch.object(self.broker, "BACKEND_USER_AGENT", "CI-Scope-Broker/9.9"),
        ):
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
            dict(
                BACKEND_QUEUE_JOB,
                repositorySlug="ForkHorizon/moodling",
                labels=["self-hosted", "macOS", "ARM64", "moodling"],
            ),
            ["self-hosted", "macOS", "ARM64", "ci-scope-broker", "moodling", "deepseek"],
        )
        self.assertEqual(job["labels"], ["self-hosted", "macOS", "ARM64", "moodling"])

    def test_server_job_payload_rejects_unmanaged_repo(self):
        self.assertIsNone(
            self._server_job(
                dict(BACKEND_QUEUE_JOB, repositorySlug="Stranger/repo"),
                ["self-hosted", "macOS", "ARM64", "ci-scope-broker"],
            )
        )

    def test_server_job_payload_rejects_job_machine_cannot_satisfy(self):
        self.assertIsNone(
            self._server_job(
                dict(
                    BACKEND_QUEUE_JOB,
                    repositorySlug="ForkHorizon/moodling",
                    labels=["self-hosted", "macOS", "ARM64", "gpu"],
                ),
                ["self-hosted", "macOS", "ARM64", "ci-scope-broker"],
            )
        )

    def test_server_status_posts_to_worker_action_endpoint(self):
        calls = []

        with (
            patch.object(self.broker, "BACKEND_URL", "https://ci.example.com"),
            patch.object(self.broker, "SERVER_MODE", True),
            patch.object(
                self.broker,
                "server_post_json",
                lambda path, payload: calls.append((path, payload)) or {"ok": True},
            ),
        ):
            self.broker.server_post_status(
                {"id": "ForkHorizon/Widget:1001:2002", "runnerName": "ci-scope-2002-12345"},
                "in_progress",
            )

        self.assertEqual(calls[0][0], "/api/ci/local/actions/ForkHorizon%2FWidget%3A1001%3A2002/status")
        self.assertEqual(calls[0][1]["status"], "in_progress")
        self.assertEqual(calls[0][1]["runnerName"], "ci-scope-2002-12345")


if __name__ == "__main__":
    unittest.main()
