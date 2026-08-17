# CI Scope v2 workspace handoff

This workspace spans three repositories:

- Client: `/Users/daliys/Daliys/Swift/CI Scope`
- Web: `/Users/daliys/Daliys/Web/CI-Scope-Web`
- Gates: `/Users/daliys/Daliys/ci-gates`

## Disposable Cloudflare staging

The disposable V2 Worker is deployed as `forkhorizon`:

- URL: `https://forkhorizon.ci-scope-web.workers.dev`
- Cloudflare D1: `ci-scope-web-staging-db`
- Worker config: `/Users/daliys/Daliys/Web/CI-Scope-Web/wrangler.jsonc`
- Deployment helper: `/Users/daliys/Daliys/Web/CI-Scope-Web/scripts/deploy-staging.sh`

The generated staging secrets are stored only on this Mac at:

```text
/Users/daliys/.config/ci-scope/staging.secrets
```

The file must remain outside Git, must have mode `600`, and must never be
printed, copied into a prompt, committed, or pasted into chat. A new agent may
read it only as an input to a local command that needs the secret values.

From the Web repository, use the helper for a redeploy:

```sh
./scripts/deploy-staging.sh
```

Production topology is separate from staging. Its Worker is
`ci-scope-web-production`, its D1 is
`ci-scope-web-production-db` (ID
`9196960f-1021-4938-a5e6-1785219ebe0b`), and production Cloudflare secrets
are provisioned in macOS Keychain by
`/Users/daliys/Daliys/Swift/CI Scope/scripts/provision-production-keychain.sh`.
The Web repository deploy helper streams those Keychain values to Wrangler;
no production secret file is used.
The latest retained production Worker deployment is
`9e313f68-5056-43e5-8353-2d7b4b91887f`; it remains the rollback path. The
purchased VPS is the active migration target, and GitHub App side effects are
disabled there after the controlled canary. Do not enable them outside an
explicit canary window.

The helper validates the local file and required key names without printing
secret values. It accepts `CI_SCOPE_SECRETS_FILE` when a different local path
is intentionally used.

## Current V2 state

- D1 migrations are applied remotely.
- VPS `/api/ci/v2/health` returns `200` with the generated shadow token and
  `x-ci-scope-runtime-mode: vps`; Cloudflare quota is relevant only to the
  retained rollback path.
- Admin Basic Auth returns `200` with the generated disposable credentials.
- The Agent/Worker session path now forwards credential proof through shadow
  `session.open`.
- Full disposable Agent lifecycle testing passed remotely with a fresh
  enrolled device credential; repeat runs must use fresh tokenId and
  credentialId values because the Durable Object keeps one-time records.
  Do not treat the shadow token as a device credential.

Read `CI_SCOPE_V2_FULL_LAUNCH_REPORT.md` and the Web handoff before changing
cross-repository ownership or deployment behavior.

The active migration plan for replacing Cloudflare with the purchased VPS is
`CI_SCOPE_V2_VPS_MIGRATION_PLAN.md`. Cloudflare remains the rollback path until
the VPS canary, soak, and rollback evidence are complete.

The first VPS control-plane slice is now deployed at `https://ci.forkhorizon.com`:

- service directory: `/opt/ci-scope-web`;
- systemd unit: `ci-scope-web.service`;
- runtime mode: `vps`;
- local V2 state database: `/opt/ci-scope-web/data/ci-scope-v2.db`;
- authenticated `/api/ci/v2/health` returns `200` with
  `x-ci-scope-runtime-mode: vps`;
- GitHub App side effects are intentionally disabled until the canary gate.
- VPS SQLite state is backed up to `/opt/ci-scope-web/backups` by the enabled
  `ci-scope-web-backup.timer`; backup files are mode `600` and pass
  `PRAGMA integrity_check`.
- VPS startup applies the checked-in SQL migrations before scheduled
  maintenance. Do not remove this startup migration step when changing the
  database adapter.

A disposable VPS protocol canary has passed fresh enrollment, `session.open`,
heartbeat and graceful Agent close. A later controlled live canary started a
real `ForkHorizon/CI-Scope` Code Linter job on the `ci-scope-v2-canary` group;
job `95194055597` succeeded and the second job was cancelled because the
canary had one VPS slot. The missing live projection root cause was fixed:
GitHub does not always include the internal JIT `preparation_id` in
`workflow_job`; Web now accepts that event shape while retaining runner
name/group matching. Deferred stale-session recovery was also fixed so a new
active session on the same machine can apply independently verified cleanup,
and terminal observer intents no longer remain pending after a reservation is
already terminal. The fixes are deployed and locally tested. Controlled
recovery cancelled the old orphan reservation, all eight observer intents are
completed, and the VPS slot is available. The Agent is stopped and App side
effects are disabled again. A clean repeat canary is still required to prove
real webhook projection end to end.

Do not start the macOS Agent or enable the GitHub canary against the VPS
outside a controlled canary window. The remaining gates are clean webhook
projection in a repeat canary, soak, rollback drill, and release-manifest/PR
acceptance.

The `ForkHorizon/ci-gates` routing fix is published on
`daliys/vps-canary-group-fix` in draft PR #66; do not merge it until the release
owner reviews the pinned gates SHA and the remaining canary evidence.

The Agent runner launcher is checked in at
`/Users/daliys/Daliys/Swift/CI Scope/scripts/ci-scope-runner-wrapper.sh`. It
must be configured as `CI_SCOPE_RUNNER_EXECUTABLE`, with the stock Actions
`run.sh` as `CI_SCOPE_RUNNER_SCRIPT`; it supervises the stock wrapper so Agent
shutdown forwards termination and cannot leave an orphan `Runner.Listener`.
