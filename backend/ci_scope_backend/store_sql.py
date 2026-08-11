SCHEMA_SQL = """
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

INSERT_EVENT_SQL = """
insert or ignore into events
(delivery_id, event, action, installation_id, repository_slug, created_at, payload_json)
values (?, ?, ?, ?, ?, ?, ?)
"""

UPSERT_REPOSITORY_SQL = """
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
"""

UPSERT_RUN_SQL = """
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
"""

UPSERT_JOB_SQL = """
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
"""

SNAPSHOT_REPOSITORIES_SQL = """
select slug, name, private, archived, deleted, url, updated_at as updatedAt
from repositories
where deleted = 0
order by slug
"""

SNAPSHOT_RUNS_SQL = """
select * from workflow_runs
order by coalesce(updated_at, created_at) desc
limit 200
"""

SNAPSHOT_JOBS_SQL = """
select * from workflow_jobs
where status in ('queued', 'in_progress')
order by coalesce(started_at, created_at) asc
limit 300
"""

EVENTS_AFTER_SQL = """
select id, event, action, payload_json
from events
where id > ?
order by id asc
limit ?
"""

ADMIN_LATEST_EVENT_SQL = """
select id, delivery_id as deliveryId, event, action, repository_slug as repositorySlug, created_at as createdAt
from events
order by id desc
limit 1
"""

ADMIN_RECENT_EVENTS_SQL = """
select id, delivery_id as deliveryId, event, action, repository_slug as repositorySlug, created_at as createdAt
from events
order by id desc
limit 20
"""

ADMIN_RECENT_RUNS_SQL = """
select * from workflow_runs
order by coalesce(updated_at, created_at) desc
limit 20
"""

ADMIN_RECENT_JOBS_SQL = """
select * from workflow_jobs
order by coalesce(updated_at, created_at) desc
limit 20
"""

ADMIN_QUEUED_JOBS_SQL = """
select * from workflow_jobs
where status = 'queued'
order by coalesce(started_at, created_at) asc
limit 100
"""

ADMIN_IN_PROGRESS_JOBS_SQL = """
select * from workflow_jobs
where status = 'in_progress'
order by coalesce(started_at, created_at) asc
limit 100
"""
