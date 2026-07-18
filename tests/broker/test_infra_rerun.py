import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))

from backend_broker_testkit import load_broker


class InfraRerunTests(unittest.TestCase):
    def setUp(self):
        self.broker = load_broker()

    def test_rerun_runs_gh_and_acks(self):
        gh_calls = []
        posts = []

        def fake_run(command, **_kwargs):
            gh_calls.append(command)
            return SimpleNamespace(returncode=0, stdout="", stderr="")

        with (
            patch.object(self.broker.subprocess, "run", fake_run),
            patch.object(self.broker, "server_post_json", lambda path, payload: posts.append((path, payload)) or {}),
        ):
            self.broker.process_pending_reruns([{"repositorySlug": "ForkHorizon/Widget", "runId": 42}])

        self.assertEqual(gh_calls[0], ["gh", "run", "rerun", "42", "--repo", "ForkHorizon/Widget", "--failed"])
        self.assertEqual(posts[0][0], "/api/ci/local/reruns/ack")
        self.assertEqual(posts[0][1]["reruns"], [{"repositorySlug": "ForkHorizon/Widget", "runId": 42}])

    def test_acks_even_when_gh_fails(self):
        posts = []

        def fake_run(_command, **_kwargs):
            return SimpleNamespace(returncode=1, stdout="", stderr="run not rerunnable")

        with (
            patch.object(self.broker.subprocess, "run", fake_run),
            patch.object(self.broker, "server_post_json", lambda path, payload: posts.append((path, payload)) or {}),
        ):
            self.broker.process_pending_reruns([{"repositorySlug": "a/b", "runId": 1}])

        # Acked on attempt so a permanently-failing run doesn't loop every heartbeat.
        self.assertEqual(posts[0][0], "/api/ci/local/reruns/ack")

    def test_empty_list_does_nothing(self):
        posts = []
        with patch.object(self.broker, "server_post_json", lambda path, payload: posts.append((path, payload)) or {}):
            self.broker.process_pending_reruns([])
        self.assertEqual(posts, [])

    def test_skips_malformed_entries(self):
        gh_calls = []
        with (
            patch.object(self.broker.subprocess, "run", lambda command, **_k: gh_calls.append(command) or SimpleNamespace(returncode=0, stdout="", stderr="")),
            patch.object(self.broker, "server_post_json", lambda path, payload: {}),
        ):
            self.broker.process_pending_reruns([{"repositorySlug": "a/b"}, {"runId": 5}, {}])
        self.assertEqual(gh_calls, [])


if __name__ == "__main__":
    unittest.main()
