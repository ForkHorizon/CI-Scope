# CI Scope v2 — VPS Control Plane Migration Plan

Status: implementation in progress; Cloudflare production remains available for rollback.

Implemented first slice:

- explicit `CI_SCOPE_RUNTIME_MODE=vps|cloudflare` on the VPS Node entrypoint;
- shared V2 ingress routed to a VPS-created RunnerPool runtime;
- SQLite-backed durable key/value state for the V2 runtime;
- VPS HTTP smoke and authenticated health checks;
- release manifest support for `deployment_kind: vps` and HTTPS endpoint evidence.

The first slice is deployed on the purchased VPS at `https://ci.forkhorizon.com`
with `CI_SCOPE_RUNTIME_MODE=vps`; live authenticated health returned `200` and
the runtime header `x-ci-scope-runtime-mode: vps`. GitHub App side effects are
disabled on this deployment.

The disposable VPS protocol canary also passed: fresh enrollment token,
Agent enrollment, `session.open`, heartbeat loop and graceful close completed
with exit status zero. No runner or GitHub side effect was enabled.

The VPS slice is not production-ready yet: PostgreSQL decision/migration,
soak and rollback drill remain required. VPS
secrets are provisioned outside Git; the GitHub App key is installed with mode
`600`, but App side effects remain disabled. SQLite backup protection is now
installed on the VPS: `/opt/ci-scope-web/backups`, mode `700`, daily
`ci-scope-web-backup.timer`, backup files mode `600`, and an integrity check on
every backup. VPS startup now applies the checked-in migrations before the
scheduled maintenance tick.

The gates canary routing fix is now published on branch
`daliys/vps-canary-group-fix` in draft PR
`https://github.com/ForkHorizon/ci-gates/pull/66`. Routing validation passed.
The live `ForkHorizon/CI-Scope` canary also started a real self-hosted Code
Linter job on `ci-scope-v2-canary`; job `95194055597` completed successfully.
The second same-label job (`95194062907`) was cancelled deliberately because
the controlled canary had one VPS slot.

That canary exposed and fixed a real cleanup race: stale scheduler revisions
are retried once without the optimistic fence, and observer-backed release now
accepts a terminal job whose local stop event was lost, confirms GitHub runner
absence, and releases the slot even when the last server runner state was
`online_idle`. Regression coverage passes in Go and TypeScript, and the fix was
deployed to the VPS. A follow-up recovery run proved the old orphaned
reservation was cancelled and the slot returned to `available`. Deferred
observer recovery now selects a replacement active session on the same machine
when the original owner is fenced, and terminal reservations short-circuit
stale observer intents instead of retrying forever.

The Agent and GitHub App side effects are disabled again after the controlled
canary. The repository webhook was corrected to
`https://ci.forkhorizon.com/api/ci/v2/webhooks/github`, and GitHub delivery
records for the real run are now visible. The missing `preparation_id` contract
shape was the projection gap's root cause and is fixed in the deployed Web
runtime. The clean repeat canary passed on run `31968552186`: both jobs
(`95217329078`, `95217329112`) succeeded, assignment and terminal projection
were observed, runners were removed before slot release, and the outbox was
empty. A second controlled wrapper canary passed on run `31969159516` (jobs
`95218749756` and `95218749852`, both successful) and exercised queued-job
recovery after an Agent restart. A transient orphan listener was observed
during that run; the checked-in macOS wrapper now terminates the complete
runner process group, and its synthetic process-group test passes. Soak and
rollback remain required before fleet cutover.

The controlled recovery of cancelled run `31967231777` also found a response
contract defect in the stale-reservation path: `retry` incorrectly included a
dispatch payload. The Web fix is deployed and covered by regression tests. The
recovery cleanup completed with an available slot, no pending work, completed
observer intents, GitHub App effects disabled, and no disposable GitHub
runners remaining. This recovery run does not count as the clean repeat
canary; the canary must still prove live assignment and terminal projection.

Agent recovery also now clears a locally released reservation when a fresh
session fences the old session and the server correctly returns
`operation_not_found` for the old status request. This is covered by a Go
regression test; the disposable VPS state is currently clean with no pending
work or observer intents.

Root cause identified after the canary: GitHub's production `workflow_job`
payload does not always include the internal JIT `preparation_id`. The Web
contract previously quarantined those events before persisting them. The
contract now accepts a missing preparation id while requiring runner id, name,
and group, and the scheduler matcher treats the preparation id as an optional
secondary check. Contract and end-to-end regression tests pass, and the fix is
deployed to the VPS. A fresh canary is still required to prove real delivery.

## Objective

Move the production CI Scope control plane from Cloudflare Worker + RunnerPool
Durable Object + D1 to the purchased VPS, while preserving the V2 HTTP
protocol, Agent state model, fencing, idempotency, reconciliation, and gates
contracts.

Target topology:

```text
macOS Agent -> HTTPS VPS API -> PostgreSQL (production)
GitHub Webhooks -> HTTPS VPS API
VPS API -> GitHub App/API
Swift UI -> local Agent Unix socket
```

Cloudflare staging and production are not deleted until VPS canary, soak, and
rollback evidence are complete.

## Ownership after migration

- VPS service: sessions, epochs, pool routing, slots, reservations, runner
  instances, idempotency, webhook inbox, outbox, reconciliation, audit and
  GitHub side effects.
- PostgreSQL: authoritative state and durable projection/history.
- Agent: PID/process group/runner directory facts, local intents/retries and
  local control lease.
- Swift UI: local Agent client only.
- ci-gates: workflow/routing/trust/release enforcement only.
- GitHub: job assignment and terminal conclusion truth.

## Implementation phases

### Phase 0 — baseline and compatibility

- Record clean/dirty state and current release SHAs in a migration manifest.
- Freeze the existing V2 endpoint and response envelope contracts.
- Inventory every Worker/DO/D1 binding and every Agent endpoint consumer.
- Define VPS hostname, TLS, firewall, service user, database, secret paths and
  rollback URL.

### Phase 1 — VPS server slice

- Reuse `Web/CI-Scope-Web/server/index.mjs` as the HTTP entrypoint.
- Keep the existing Worker-compatible routing and validation where possible.
- Add a VPS persistence adapter with the same authoritative state transitions.
- Add durable idempotency, fencing, webhook inbox, outbox and retry state.
- Add a single active scheduler with a database-backed lease.
- Add bounded reconciliation and operator-visible retry exhaustion.
- Add `/health` and authenticated operation-status/read-model endpoints.

SQLite remains useful for local tests and development. Production should use
PostgreSQL unless the VPS deployment is explicitly single-process and backed
up; the migration must not silently rely on process memory for authority.

### Phase 2 — GitHub and operations

- Move GitHub App private key, webhook secret and admin credentials to the VPS
  secret mechanism; never commit or log them.
- Connect GitHub webhook verification, JIT preparation, runner observation and
  cleanup directly to the VPS service.
- Install systemd service, Nginx/Caddy TLS, firewall rules, backups, logs,
  restart policy and alerts.

Current VPS operations status:

- `ci-scope-web.service` is active under systemd with `Restart=on-failure`.
- `ci-scope-web-backup.timer` is enabled and runs at 03:15 UTC daily.
- A real backup has been created and verified with `PRAGMA integrity_check`.
- The VPS startup path applies the SQL migrations before maintenance and was
  verified with a local scheduled-maintenance smoke test.

### Phase 3 — Agent and gates cutover

- Make the Agent control-plane URL configurable and point a canary Agent to
  the VPS endpoint.
- Preserve enrollment, `session.open`, heartbeat, reconcile, close, claim,
  reservation and runner lifecycle envelopes.
- Update gates release metadata and canonical endpoint checks; no scheduler
  logic moves into ci-gates.

### Phase 4 — verification and cutover

- Run contract, duplicate webhook, lost response, retry, stale epoch, server
  restart, database recovery and network-partition tests (PASSED).
- Run repeat controlled canary with multi-job matrix: `ForkHorizon/CI-Scope#32072265866`
  (PASSED: both Canary A and Canary B jobs succeeded on VPS slot-1).
- Webhook ingress filtering verified: hosted jobs are quarantined and omitted
  from self-hosted queue (PASSED).
- Immediate VPS alarm timer dispatch verified: observer intents and releases
  complete without latency (PASSED).
- Post-canary safety gate: GitHub App side effects disabled on VPS, Agent unloaded.
- Complete soak period and rollback drill.
- Switch remaining Agents one at a time.
- Retain Cloudflare as rollback until the VPS release is accepted; remove it in
  a separate cleanup change.

## Definition of done

- No production Agent request depends on Worker/DO/D1.
- VPS restart does not lose authoritative state or duplicate GitHub side effects.
- Duplicate/lost webhooks and ambiguous GitHub responses reconcile safely.
- One scheduler authority and one active routing generation are proven.
- TLS, authentication, secrets, backups, monitoring and rollback are tested.
- Client, server and gates release manifests contain fixed VPS deployment
  identity and compatible protocol versions.
