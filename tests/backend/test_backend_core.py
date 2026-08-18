import hashlib
import hmac
import json
import tempfile
import unittest
from pathlib import Path

import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend"))

from ci_scope_backend.core import normalize_webhook, verify_signature  # noqa: E402
from ci_scope_backend.store import SQLiteStore  # noqa: E402

try:
    from ci_scope_backend.app import require_client  # noqa: E402
    from fastapi import HTTPException  # noqa: E402
except ModuleNotFoundError:
    require_client = None
    HTTPException = None


def workflow_job_payload(action="queued", status="queued"):
    return {
        "action": action,
        "installation": {"id": 42},
        "repository": {
            "full_name": "ForkHorizon/Widget",
            "name": "Widget",
            "private": True,
            "archived": False,
            "html_url": "https://github.com/ForkHorizon/Widget",
        },
        "workflow_run": {
            "id": 1001,
            "name": "CI",
            "display_title": "Run tests",
            "head_branch": "feature/events",
            "status": "in_progress" if status != "completed" else "completed",
            "conclusion": None if status != "completed" else "success",
            "html_url": "https://github.com/ForkHorizon/Widget/actions/runs/1001",
            "event": "pull_request",
            "created_at": "2026-06-15T10:00:00Z",
            "updated_at": "2026-06-15T10:00:10Z",
        },
        "workflow_job": {
            "id": 2002,
            "run_id": 1001,
            "workflow_name": "CI",
            "name": "quality",
            "head_branch": "feature/events",
            "status": status,
            "conclusion": None if status != "completed" else "success",
            "html_url": "https://github.com/ForkHorizon/Widget/actions/runs/1001/job/2002",
            "created_at": "2026-06-15T10:00:01Z",
            "started_at": None,
            "completed_at": None,
            "runner_name": None,
            "labels": ["self-hosted", "macOS", "ARM64", "ci-scope-broker"],
        },
    }


def workflow_job_payload_for(job_id, run_id, action="queued", status="queued"):
    payload = workflow_job_payload(action=action, status=status)
    payload["workflow_run"]["id"] = run_id
    payload["workflow_job"]["run_id"] = run_id
    payload["workflow_job"]["id"] = job_id
    return payload


class BackendCoreTests(unittest.TestCase):
    def test_verify_signature(self):
        secret = "top-secret"
        body = b'{"ok":true}'
        digest = hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()
        self.assertTrue(verify_signature(body, f"sha256={digest}", secret))
        self.assertFalse(verify_signature(body, "sha256=bad", secret))
        self.assertFalse(verify_signature(body, f"sha256={digest}", "wrong"))

    def test_normalizes_workflow_job(self):
        normalized = normalize_webhook(
            "workflow_job", "delivery-1", workflow_job_payload()
        )
        self.assertEqual(normalized["installationId"], 42)
        self.assertEqual(normalized["repositorySlug"], "ForkHorizon/Widget")
        self.assertEqual(normalized["run"]["id"], 1001)
        self.assertEqual(normalized["job"]["id"], 2002)
        self.assertEqual(
            normalized["job"]["labels"],
            ["self-hosted", "macOS", "ARM64", "ci-scope-broker"],
        )

    def test_store_deduplicates_deliveries_and_tracks_queue_transitions(self):
        with tempfile.TemporaryDirectory() as directory:
            store = SQLiteStore(Path(directory) / "state.sqlite3")
            first = store.record_webhook(
                "workflow_job", "delivery-1", workflow_job_payload()
            )
            duplicate = store.record_webhook(
                "workflow_job", "delivery-1", workflow_job_payload()
            )
            snapshot = store.snapshot()

            self.assertFalse(first["duplicate"])
            self.assertTrue(duplicate["duplicate"])
            self.assertEqual(len(snapshot["jobs"]), 1)
            self.assertEqual(snapshot["jobs"][0]["status"], "queued")

            completed = workflow_job_payload(action="completed", status="completed")
            completed["workflow_run"]["conclusion"] = "success"
            completed["workflow_job"]["conclusion"] = "success"
            store.record_webhook("workflow_job", "delivery-2", completed)
            snapshot = store.snapshot()

            self.assertEqual(snapshot["jobs"], [])
            self.assertEqual(snapshot["runs"][0]["status"], "completed")
            self.assertEqual(snapshot["runs"][0]["conclusion"], "success")

    def test_snapshot_keeps_queued_jobs_while_broker_is_offline(self):
        with tempfile.TemporaryDirectory() as directory:
            store = SQLiteStore(Path(directory) / "state.sqlite3")
            store.record_webhook("workflow_job", "delivery-1", workflow_job_payload())

            first_snapshot = store.snapshot()
            later_snapshot = store.snapshot()

            self.assertEqual(first_snapshot["eventId"], later_snapshot["eventId"])
            self.assertEqual(len(later_snapshot["jobs"]), 1)
            self.assertEqual(later_snapshot["jobs"][0]["status"], "queued")

    def test_snapshot_is_json_serializable(self):
        with tempfile.TemporaryDirectory() as directory:
            store = SQLiteStore(Path(directory) / "state.sqlite3")
            store.record_webhook("workflow_job", "delivery-1", workflow_job_payload())
            json.dumps(store.snapshot())

    def test_admin_status_counts_events_runs_jobs_and_sse_clients(self):
        with tempfile.TemporaryDirectory() as directory:
            store = SQLiteStore(Path(directory) / "state.sqlite3")
            store.record_webhook(
                "workflow_job", "delivery-1", workflow_job_payload_for(2002, 1001)
            )
            store.record_webhook(
                "workflow_job",
                "delivery-2",
                workflow_job_payload_for(
                    2003, 1002, action="in_progress", status="in_progress"
                ),
            )
            store.record_webhook(
                "workflow_job",
                "delivery-3",
                workflow_job_payload_for(
                    2004, 1003, action="completed", status="completed"
                ),
            )

            status = store.admin_status(active_sse_clients=2)

            self.assertEqual(status["sse"]["activeClients"], 2)
            self.assertEqual(status["events"]["total"], 3)
            self.assertEqual(status["events"]["latest"]["deliveryId"], "delivery-3")
            self.assertEqual(status["repositories"]["total"], 1)
            self.assertEqual(
                status["jobs"]["byStatus"],
                {"completed": 1, "in_progress": 1, "queued": 1},
            )
            self.assertEqual(len(status["jobs"]["queued"]), 1)
            self.assertEqual(len(status["jobs"]["inProgress"]), 1)

    @unittest.skipIf(
        require_client is None or HTTPException is None, "FastAPI is not installed"
    )
    def test_admin_status_auth_guard_uses_bearer_token(self):
        require_client("Bearer secret", "secret")
        with self.assertRaises(HTTPException):
            require_client("Bearer wrong", "secret")


if __name__ == "__main__":
    unittest.main()
