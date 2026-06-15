from __future__ import annotations

import json
import sqlite3
from pathlib import Path
from typing import Any

from .core import normalize_webhook, now_iso
from .store_sql import (
    EVENTS_AFTER_SQL,
    INSERT_EVENT_SQL,
    SCHEMA_SQL,
    SNAPSHOT_JOBS_SQL,
    SNAPSHOT_REPOSITORIES_SQL,
    SNAPSHOT_RUNS_SQL,
    UPSERT_JOB_SQL,
    UPSERT_REPOSITORY_SQL,
    UPSERT_RUN_SQL,
)


def repositories_from(normalized: dict[str, Any]) -> list[dict[str, Any]]:
    repositories = []
    if normalized.get("repository"):
        repositories.append(normalized["repository"])
    repositories.extend(normalized.get("repositories") or [])
    return repositories


class SQLiteStore:
    def __init__(self, path: str | Path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.init_schema()

    def connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path)
        connection.row_factory = sqlite3.Row
        return connection

    def init_schema(self) -> None:
        with self.connect() as db:
            db.executescript(SCHEMA_SQL)

    def record_webhook(self, event: str, delivery_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        normalized = normalize_webhook(event, delivery_id, payload)
        installation_id = normalized.get("installationId") or 0
        now = normalized["receivedAt"]
        with self.connect() as db:
            inserted = db.execute(
                INSERT_EVENT_SQL,
                (
                    delivery_id,
                    event,
                    normalized.get("action"),
                    installation_id,
                    normalized.get("repositorySlug"),
                    now,
                    json.dumps(normalized, sort_keys=True),
                ),
            ).rowcount
            if inserted == 0:
                row = db.execute("select id from events where delivery_id = ?", (delivery_id,)).fetchone()
                return {"duplicate": True, "eventId": int(row["id"]) if row else self.latest_event_id(db), "normalized": normalized}

            self.upsert_records(db, installation_id, normalized)
            event_id = int(db.execute("select last_insert_rowid()").fetchone()[0])
        normalized["eventId"] = event_id
        return {"duplicate": False, "eventId": event_id, "normalized": normalized}

    def upsert_records(self, db: sqlite3.Connection, installation_id: int, normalized: dict[str, Any]) -> None:
        for repository in repositories_from(normalized):
            self.upsert_repository(db, installation_id, repository)
        if normalized.get("run"):
            self.upsert_run(db, installation_id, normalized["run"])
        if normalized.get("job"):
            self.upsert_job(db, installation_id, normalized["job"])

    def upsert_repository(
        self,
        db: sqlite3.Connection,
        installation_id: int,
        repository: dict[str, Any],
    ) -> None:
        deleted = 1 if repository.get("installationAction") == "removed" else int(repository.get("deleted", False))
        values = (
            installation_id,
            repository["slug"],
            repository.get("name"),
            int(repository.get("private", False)),
            int(repository.get("archived", False)),
            deleted,
            repository.get("url"),
            repository.get("updatedAt") or now_iso(),
        )
        db.execute(UPSERT_REPOSITORY_SQL, values)

    def upsert_run(self, db: sqlite3.Connection, installation_id: int, run: dict[str, Any]) -> None:
        values = (
            installation_id,
            run["repositorySlug"],
            run["id"],
            run.get("workflowName"),
            run.get("displayTitle"),
            run.get("headBranch"),
            run.get("status"),
            run.get("conclusion"),
            run.get("url"),
            run.get("event"),
            run.get("createdAt"),
            run.get("updatedAt") or now_iso(),
            json.dumps(run, sort_keys=True),
        )
        db.execute(UPSERT_RUN_SQL, values)

    def upsert_job(self, db: sqlite3.Connection, installation_id: int, job: dict[str, Any]) -> None:
        values = (
            installation_id,
            job["repositorySlug"],
            job["runId"],
            job["id"],
            job.get("workflowName"),
            job.get("title"),
            job.get("jobName"),
            job.get("headBranch"),
            job.get("status"),
            job.get("conclusion"),
            job.get("url"),
            job.get("createdAt"),
            job.get("startedAt"),
            job.get("completedAt"),
            job.get("runnerName"),
            json.dumps(job.get("labels") or [], sort_keys=True),
            now_iso(),
            json.dumps(job, sort_keys=True),
        )
        db.execute(UPSERT_JOB_SQL, values)

    def snapshot(self) -> dict[str, Any]:
        with self.connect() as db:
            event_id = self.latest_event_id(db)
            repositories = [
                dict(row)
                for row in db.execute(SNAPSHOT_REPOSITORIES_SQL)
            ]
            runs = [
                self.run_from_row(row)
                for row in db.execute(SNAPSHOT_RUNS_SQL)
            ]
            jobs = [
                self.job_from_row(row)
                for row in db.execute(SNAPSHOT_JOBS_SQL)
            ]
        return {
            "version": 1,
            "generatedAt": now_iso(),
            "eventId": event_id,
            "repositories": repositories,
            "runs": runs,
            "jobs": jobs,
        }

    def events_after(self, last_event_id: int, limit: int = 100) -> list[dict[str, Any]]:
        with self.connect() as db:
            rows = db.execute(
                EVENTS_AFTER_SQL,
                (last_event_id, limit),
            ).fetchall()
        return [
            {
                "id": int(row["id"]),
                "event": row["event"],
                "action": row["action"],
                "payload": json.loads(row["payload_json"]),
            }
            for row in rows
        ]

    def latest_event_id(self, db: sqlite3.Connection | None = None) -> int:
        owns_connection = db is None
        if db is None:
            db = self.connect()
        try:
            value = db.execute("select coalesce(max(id), 0) from events").fetchone()[0]
            return int(value or 0)
        finally:
            if owns_connection:
                db.close()

    @staticmethod
    def run_from_row(row: sqlite3.Row) -> dict[str, Any]:
        return {
            "id": int(row["run_id"]),
            "repositorySlug": row["repository_slug"],
            "workflowName": row["workflow_name"] or "Workflow",
            "displayTitle": row["display_title"] or row["workflow_name"] or "Workflow run",
            "headBranch": row["head_branch"] or "-",
            "status": row["status"] or "queued",
            "conclusion": row["conclusion"],
            "url": row["url"] or "",
            "event": row["event"] or "",
            "createdAt": row["created_at"] or now_iso(),
            "updatedAt": row["updated_at"] or row["created_at"] or now_iso(),
        }

    @staticmethod
    def job_from_row(row: sqlite3.Row) -> dict[str, Any]:
        return {
            "id": int(row["job_id"]),
            "runId": int(row["run_id"]),
            "repositorySlug": row["repository_slug"],
            "workflowName": row["workflow_name"] or "Workflow",
            "title": row["title"] or row["workflow_name"] or "Workflow run",
            "jobName": row["job_name"] or "Workflow job",
            "headBranch": row["head_branch"] or "-",
            "status": row["status"] or "queued",
            "conclusion": row["conclusion"],
            "url": row["url"] or "",
            "createdAt": row["created_at"] or now_iso(),
            "startedAt": row["started_at"],
            "completedAt": row["completed_at"],
            "runnerName": row["runner_name"],
            "labels": json.loads(row["labels_json"] or "[]"),
        }
