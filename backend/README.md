# CI Scope GitHub App Backend

Small event relay for CI Scope. GitHub sends App webhooks here, the backend
stores normalized CI state in SQLite, and each Mac broker connects outbound via
SSE instead of polling GitHub.

## Environment

```text
CI_SCOPE_BACKEND_DB=./ci-scope-backend.sqlite3
CI_SCOPE_WEBHOOK_SECRET=github-webhook-secret
CI_SCOPE_CLIENT_TOKEN=shared-mac-client-token
```

## Run

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r backend/requirements.txt
uvicorn ci_scope_backend.app:app --app-dir backend --host 0.0.0.0 --port 8080
```

Configure the GitHub App webhook URL to:

```text
https://your-backend.example.com/github/webhook
```

Subscribe the app to `workflow_job`, `workflow_run`, `push`, `repository`, and
`installation_repositories`.

Point the Mac broker at the backend:

```text
CI_SCOPE_BACKEND_URL=https://your-backend.example.com
CI_SCOPE_BACKEND_TOKEN=shared-mac-client-token
```
