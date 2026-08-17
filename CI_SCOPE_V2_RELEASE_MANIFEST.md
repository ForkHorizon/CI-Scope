# CI Scope v2 cross-repository release manifest

Status: `DRAFT — ACTIVATION BLOCKED`

This is the integration manifest for Client, Web, and Gates. It is deliberately
not a release assertion: local tests cannot prove a GitHub workflow run SHA or
a Cloudflare deployment ID. Fill every `TBD` from authoritative external
evidence after the quota reset, then run the Gates release validator.

## Release identity

| Field | Value | Evidence required |
|---|---|---|
| Manifest version | `1` | Checked-in contract |
| Routing generation | `v2` | Consumer workflow + Worker config |
| Protocol range | `2..2` | Client Agent, Web protocol |
| DO schema version | `TBD` | Web migration/config |
| D1 projection version | `TBD` | Web migration/projection |
| Activation timestamp | `TBD` | UTC timestamp of approved activation |
| Rollback target | `TBD` | Immutable prior release commit |
| Activation barrier | `BLOCKED` | Must become `GREEN` only after all evidence below |

## Repository revisions

Record immutable commit SHAs after the three repositories are cleanly staged
for release. A dirty working tree is not release evidence.

| Component | Repository | Commit SHA | Local checks |
|---|---|---|---|
| Client + Agent | `ForkHorizon/CI-Scope` | `TBD` | Swift build/tests; Agent go test/race/vet |
| Worker + DO | `ForkHorizon/CI-Scope-Web` | `TBD` | Web tests/typecheck/build |
| Gates | `ForkHorizon/ci-gates` | `TBD` | pytest/compile/actionlint |

## VPS canary evidence

The active migration target is the purchased VPS, not the retained Cloudflare
rollback deployment:

| Evidence | Value | Result |
|---|---|---|
| VPS endpoint | `https://ci.forkhorizon.com` | Authenticated health `200`; runtime `vps` |
| Repeat clean canary run | `ForkHorizon/CI-Scope#32072265866` | Succeeded end-to-end; both `Same-label canary A` (`95518114288`) and `Same-label canary B` (`95518123512`) claimed sequentially by VPS slot-1 and completed; hosted `routing-validation` jobs properly quarantined |
| Workflow head SHA | `3b8ea16faec0ad36ea99e4f58c73aa02c462e737` | Observed from GitHub run API for run `32072265866` |
| Gates routing PR | `ci-gates#66`, branch `daliys/vps-canary-group-fix` | Draft; routing validation passed |
| Gates branch head | `bce84af833b8094defe27bb4d09eb352e7070a8f` | Pinned routing revision; draft PR Self Check passes, not merged |
| Cleanup proof | VPS RunnerPool state | Both reservations terminal (`satisfied`); slot available; observer intents completed; GitHub disposable runner list empty |
| Webhook delivery mode | Real GitHub hook deliveries observed; both canary jobs projected | Assignment and terminal projection verified for both jobs; runner removal preceded slot release |
| Runner wrapper lifecycle | Checked-in `scripts/ci-scope-runner-wrapper.sh` | Supervises Runner.Listener cleanly; shutdown forwards signals without leaving orphan processes |
| Prior canary runs | `ForkHorizon/CI-Scope#31969159516`, `#31967231777` | Validated multi-job scheduling and queued-job recovery |

## External provenance

These values must come from the GitHub/Cloudflare systems, not from a
self-declared file or local build output.

| Evidence | Value | Required proof |
|---|---|---|
| Observed canary workflow SHA | `TBD` | GitHub run API/UI for the exact canary run |
| Gates reusable workflow SHA | `TBD` | GitHub job/reusable-workflow ref observed in the run |
| Worker deployment ID | `TBD` | Cloudflare deployment record for the exact Web commit |
| Worker environment | `production` or `canary` | Cloudflare deployment record |
| Runner group | `ci-scope-v2-canary` | GitHub organization runner-group record |
| Runner group ID | `TBD` | GitHub organization record |
| Labels | `self-hosted,macOS,ARM64,ci-scope-v2` | Workflow + runner observation |

## Required activation evidence

- [ ] Gates `validate_manifest` passes with the actual `ci_gates_sha`.
- [ ] Gates release enforcement passes with the externally observed workflow
      SHA and exact reusable-workflow SHA.
- [ ] Worker `/api/ci/v2/health` returns `200` after the quota reset.
- [ ] Production JIT/Agent side effects remain disabled until the canary gate
      is explicitly approved.
- [x] A repeat canary proves both same-label jobs, one eligible routing domain,
      and no duplicate reservation/runner ownership.
- [x] Terminal cleanup proves runner removal before slot release.
- [x] Outbox projection and reconciliation evidence is recorded.
- [ ] Rollback drill is completed using the runbook in
      `CI_SCOPE_V2_ROLLBACK_RUNBOOK.md`.

## Generation barrier

Activation is permitted only when this manifest is complete, the canary
workflow and Worker use the same `routing_generation`, and the rollback target
is known to be deployable. Missing, placeholder, or self-declared external
provenance keeps `Activation barrier` at `BLOCKED`.

## Capture commands

Run locally in each repository after the final release commit:

```sh
git rev-parse HEAD
git status --short
```

Use the GitHub run/job evidence and Cloudflare deployment record to fill the
external rows. Never put secrets, bearer tokens, private keys, or device
credentials in this file.
