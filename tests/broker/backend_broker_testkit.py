"""Shared fixtures for backend broker tests."""

import importlib.machinery
import importlib.util
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


class StopLoop(Exception):
    pass


def load_broker():
    loader = importlib.machinery.SourceFileLoader("broker_unittest", str(BROKER_PATH))
    spec = importlib.util.spec_from_loader("broker_unittest", loader)
    broker = importlib.util.module_from_spec(spec)
    loader.exec_module(broker)
    return broker
