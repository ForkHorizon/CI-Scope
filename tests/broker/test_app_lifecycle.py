import os
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from backend_broker_testkit import BACKEND_QUEUE_JOB, MockProcess, load_broker


class AppHeartbeatTests(unittest.TestCase):
    def setUp(self):
        self.broker = load_broker()

    def test_active_when_heartbeat_path_unset(self):
        # Legacy always-on behaviour: no heartbeat configured -> keep running.
        self.broker.APP_HEARTBEAT_PATH = ""
        self.assertTrue(self.broker.app_is_active())

    def test_active_when_heartbeat_fresh(self):
        with tempfile.NamedTemporaryFile() as handle:
            self.broker.APP_HEARTBEAT_PATH = handle.name
            self.broker.APP_HEARTBEAT_STALE_SECONDS = 15
            os.utime(handle.name, None)  # touch to now
            self.assertTrue(self.broker.app_is_active())

    def test_inactive_when_heartbeat_stale(self):
        with tempfile.NamedTemporaryFile() as handle:
            self.broker.APP_HEARTBEAT_PATH = handle.name
            self.broker.APP_HEARTBEAT_STALE_SECONDS = 15
            old = time.time() - 60
            os.utime(handle.name, (old, old))
            self.assertFalse(self.broker.app_is_active())

    def test_inactive_when_heartbeat_missing(self):
        self.broker.APP_HEARTBEAT_PATH = "/no/such/ci-scope-heartbeat"
        self.assertFalse(self.broker.app_is_active())


class DrainTests(unittest.TestCase):
    def setUp(self):
        self.broker = load_broker()

    def test_draining_starts_no_new_runners(self):
        # A queued job is present, but with dispatch_new=False (app closed) the
        # broker must NOT start a runner for it.
        queue = [dict(BACKEND_QUEUE_JOB)]

        def mock_read_state():
            return {"version": 1, "actives": [], "queue": queue, "repos": [], "retries": {}, "webhook": {}}

        original_write_state = self.broker.write_state
        original_read_state = self.broker.read_state
        original_start_runner = self.broker.start_runner
        started = []
        try:
            self.broker.write_state = lambda *_a, **_k: None
            self.broker.read_state = mock_read_state
            self.broker.start_runner = lambda job: started.append(job) or MockProcess()
            self.broker.tick(polled=None, profiles=self.broker.DEFAULT_PROFILES, dispatch_new=False)
        finally:
            self.broker.write_state = original_write_state
            self.broker.read_state = original_read_state
            self.broker.start_runner = original_start_runner

        self.assertEqual(started, [], "no runner should start while draining")


if __name__ == "__main__":
    unittest.main()
