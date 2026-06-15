from __future__ import annotations

import json
import sqlite3
from pathlib import Path
from typing import Any

from .core import normalize_webhook, now_iso


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
            db.executescript(
                """
                create table if not exists repositories (
                  installation_id integer not null,
                  slug text not null,
                  name text,
                  private integer not null default 0,
                  archived integer not null default 0,
                  deleted integer not null default 0,
                  url text,
                  updated_at text not null,
                  primary key (installation_id, slug)
                );
                create table if not exists workflow_runs (
                  installation_id integer not null,
                  repository_slug text not null,
                  run_id integer not null,
                  workflow_name text,
                  display_title text,
                  head_branch text,
                  status text,
                  conclusion text,
                  url text,
                  event text,
                  created_at text,
                  updated_at text,
                  payload_json text not null,
                  primary key (installation_id, repository_slug, run_id)
                );
                create table if not exists workflow_jobs (
                  installation_id integer not null,
                  repository_slug text not null,
                  run_id integer not null,
                  job_id integer not null,
                  workflow_name text,
                  title text,
                  job_name text,
                  head_branch text,
                  status text,
                  conclusion text,
                  url text,
                  created_at text,
                  started_at text,
                  completed_at text,
                  runner_name text,
                  labels_json text not null,
                  updated_at text not null,
                  payload_json text not null,
                  primary key (installation_id, repository_slug, run_id, job_id)
                );
                create table if not exists events (
                  id integer primary key autoincrement,
                  delivery_id text not null unique,
                  event text not null,
                  action text,
                  installation_id integer,
                  repository_slug text,
                  created_at text not null,
                  payload_json text not null
                );
                """
            )

    def record_webhook(self, event: str, delivery_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        normalized = normalize_webhook(event, delivery_id, payload)
        installation_id = normalized.get("installationId") or 0
        now = normalized["receivedAt"]
        with self.connect() as db:
            inserted = db.execute(
                """
                insert or ignore into events
                (delivery_id, event, action, installation_id, repository_slug, created_at, payload_json)
                values (?, ?, ?, ?, ?, ?, ?)
                """,
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
        repositories = []
        if normalized.get("repository"):
            repositories.append(normalized["repository"])
        repositories.extend(normalized.get("repositories") or [])
        for repository in repositories:
            deleted = 1 if repository.get("installationAction") == "removed" else int(repository.get("deleted", False))
            db.execute(
                """
                insert into repositories
                (installation_id, slug, name, private, archived, deleted, url, updated_at)
                values (?, ?, ?, ?, ?, ?, ?, ?)
                on conflict(installation_id, slug) do update set
                  name=excluded.name,
                  private=excluded.private,
                  archived=excluded.archived,
                  deleted=excluded.deleted,
                  url=excluded.url,
                  updated_at=excluded.updated_at
                """,
                (
                    installation_id,
                    repository["slug"],
                    repository.get("name"),
                    int(repository.get("private", False)),
                    int(repository.get("archived", False)),
                    deleted,
                    repository.get("url"),
                    repository.get("updatedAt") or now_iso(),
                ),
            )

        run = normalized.get("run")
        if run:
            db.execute(
                """
                insert into workflow_runs
                (installation_id, repository_slug, run_id, workflow_name, display_title, head_branch,
                 status, conclusion, url, event, created_at, updated_at, payload_json)
                values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                on conflict(installation_id, repository_slug, run_id) do update set
                  workflow_name=excluded.workflow_name,
                  display_title=excluded.display_title,
                  head_branch=excluded.head_branch,
                  status=excluded.status,
                  conclusion=excluded.conclusion,
                  url=excluded.url,
                  event=excluded.event,
                  updated_at=excluded.updated_at,
                  payload_json=excluded.payload_json
                """,
                (
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
                ),
            )

        job = normalized.get("job")
        if job:
            db.execute(
                """
                insert into workflow_jobs
                (installation_id, repository_slug, run_id, job_id, workflow_name, title, job_name,
                 head_branch, status, conclusion, url, created_at, started_at, completed_at,
                 runner_name, labels_json, updated_at, payload_json)
                values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                on conflict(installation_id, repository_slug, run_id, job_id) do update set
                  workflow_name=excluded.workflow_name,
                  title=excluded.title,
                  job_name=excluded.job_name,
                  head_branch=excluded.head_branch,
                  status=excluded.status,
                  conclusion=excluded.conclusion,
                  url=excluded.url,
                  started_at=excluded.started_at,
                  completed_at=excluded.completed_at,
                  runner_name=excluded.runner_name,
                  labels_json=excluded.labels_json,
                  updated_at=excluded.updated_at,
                  payload_json=excluded.payload_json
                """,
                (
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
                ),
            )

    def snapshot(self) -> dict[str, Any]:
        with self.connect() as db:
            event_id = self.latest_event_id(db)
            repositories = [
                dict(row)
                for row in db.execute(
                    """
                    select slug, name, private, archived, deleted, url, updated_at as updatedAt
                    from repositories
                    where deleted = 0
                    order by slug
                    """
                )
            ]
            runs = [
                self.run_from_row(row)
                for row in db.execute(
                    """
                    select * from workflow_runs
                    order by coalesce(updated_at, created_at) desc
                    limit 200
                    """
                )
            ]
            jobs = [
                self.job_from_row(row)
                for row in db.execute(
                    """
                    select * from workflow_jobs
                    where status in ('queued', 'in_progress')
                    order by coalesce(started_at, created_at) asc
                    limit 300
                    """
                )
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
                """
                select id, event, action, payload_json
                from events
                where id > ?
                order by id asc
                limit ?
                """,
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
