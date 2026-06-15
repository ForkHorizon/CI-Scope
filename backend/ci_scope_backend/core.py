from __future__ import annotations

import hashlib
import hmac
from datetime import datetime, timezone
from typing import Any


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def verify_signature(body: bytes, signature: str, secret: str) -> bool:
    if not secret or not signature.startswith("sha256="):
        return False
    digest = hmac.new(secret.encode("utf-8"), body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(f"sha256={digest}", signature)


def normalize_webhook(event: str, delivery_id: str, payload: dict[str, Any]) -> dict[str, Any]:
    action = str(payload.get("action") or "")
    installation_id = installation_id_from(payload)
    repository = repository_record(payload.get("repository") or {})
    slug = repository.get("slug") or ""
    normalized: dict[str, Any] = {
        "version": 1,
        "event": event,
        "action": action,
        "deliveryId": delivery_id,
        "installationId": installation_id,
        "repositorySlug": slug,
        "receivedAt": now_iso(),
        "repository": repository if repository else None,
        "run": None,
        "job": None,
        "repositories": [],
    }

    if event == "workflow_job":
        normalized["run"] = run_record(slug, payload.get("workflow_run") or {})
        normalized["job"] = job_record(
            slug=slug,
            action=action,
            workflow_job=payload.get("workflow_job") or {},
            workflow_run=payload.get("workflow_run") or {},
            workflow=payload.get("workflow") or {},
        )
        if normalized["run"] is None and normalized["job"] is not None:
            normalized["run"] = run_from_job(normalized["job"])
    elif event == "workflow_run":
        normalized["run"] = run_record(slug, payload.get("workflow_run") or {})
    elif event in {"pull_request", "repository", "push"}:
        pass
    elif event == "installation_repositories":
        repositories = []
        for item in payload.get("repositories_added") or []:
            record = repository_record(item)
            if record:
                record["installationAction"] = "added"
                repositories.append(record)
        for item in payload.get("repositories_removed") or []:
            record = repository_record(item)
            if record:
                record["installationAction"] = "removed"
                repositories.append(record)
        normalized["repositories"] = repositories

    return normalized


def installation_id_from(payload: dict[str, Any]) -> int | None:
    installation = payload.get("installation") or {}
    value = installation.get("id")
    return int(value) if isinstance(value, int) or str(value).isdigit() else None


def repository_record(repository: dict[str, Any]) -> dict[str, Any]:
    slug = repository.get("full_name") or repository.get("nameWithOwner") or ""
    if not slug and repository.get("owner") and repository.get("name"):
        owner = repository["owner"]
        owner_name = owner.get("login") if isinstance(owner, dict) else owner
        slug = f"{owner_name}/{repository['name']}"
    if not slug:
        return {}
    return {
        "slug": slug,
        "name": repository.get("name") or slug.rsplit("/", 1)[-1],
        "private": bool(repository.get("private", False)),
        "archived": bool(repository.get("archived", False)),
        "deleted": False,
        "url": repository.get("html_url") or repository.get("url") or "",
        "updatedAt": now_iso(),
    }


def run_record(slug: str, run: dict[str, Any]) -> dict[str, Any] | None:
    run_id = run.get("id") or run.get("database_id")
    if run_id is None:
        return None
    return {
        "id": int(run_id),
        "repositorySlug": slug,
        "workflowName": run.get("name") or "Workflow",
        "displayTitle": run.get("display_title") or run.get("name") or "Workflow run",
        "headBranch": run.get("head_branch") or "-",
        "status": run.get("status") or "queued",
        "conclusion": run.get("conclusion"),
        "url": run.get("html_url") or "",
        "event": run.get("event") or "",
        "createdAt": run.get("created_at") or now_iso(),
        "updatedAt": run.get("updated_at") or now_iso(),
    }


def job_record(
    slug: str,
    action: str,
    workflow_job: dict[str, Any],
    workflow_run: dict[str, Any],
    workflow: dict[str, Any],
) -> dict[str, Any] | None:
    job_id = workflow_job.get("id")
    run_id = workflow_job.get("run_id") or workflow_run.get("id")
    if job_id is None or run_id is None:
        return None
    workflow_name = (
        workflow_job.get("workflow_name")
        or workflow_run.get("name")
        or workflow.get("name")
        or "Workflow"
    )
    return {
        "id": int(job_id),
        "runId": int(run_id),
        "repositorySlug": slug,
        "workflowName": workflow_name,
        "title": workflow_run.get("display_title") or workflow_job.get("name") or workflow_name,
        "jobName": workflow_job.get("name") or "Workflow job",
        "headBranch": workflow_job.get("head_branch") or workflow_run.get("head_branch") or "-",
        "status": workflow_job.get("status") or action or "queued",
        "conclusion": workflow_job.get("conclusion"),
        "url": workflow_job.get("html_url") or workflow_run.get("html_url") or "",
        "createdAt": workflow_job.get("created_at") or workflow_run.get("created_at") or now_iso(),
        "startedAt": workflow_job.get("started_at"),
        "completedAt": workflow_job.get("completed_at"),
        "runnerName": workflow_job.get("runner_name"),
        "labels": workflow_job.get("labels") or [],
    }


def run_from_job(job: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": job["runId"],
        "repositorySlug": job["repositorySlug"],
        "workflowName": job["workflowName"],
        "displayTitle": job["title"],
        "headBranch": job["headBranch"],
        "status": "in_progress" if job["status"] != "completed" else "completed",
        "conclusion": job.get("conclusion"),
        "url": job.get("url") or "",
        "event": "",
        "createdAt": job["createdAt"],
        "updatedAt": now_iso(),
    }

