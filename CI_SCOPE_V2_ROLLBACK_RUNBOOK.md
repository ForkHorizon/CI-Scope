# CI Scope v2 rollback runbook

Rollback is a controlled authority transition. It is not an immediate restart
of v1 and it never uses a D1 snapshot or runner-name deletion as proof of
cleanup.

## Preconditions

- Keep the current release manifest and the known-good rollback target.
- Confirm the rollback owner and record the incident/run ID.
- Keep production Agent/JIT disabled while the cause or Cloudflare quota state
  is unknown.

## Procedure

1. Set the v2 routing generation to drain-only; stop new v2 claims.
2. Fence v2 sessions. Do not kill a confirmed assigned job solely because the
   Worker is unavailable.
3. Reconcile queued and leased v2 work by explicit disposition: drain,
   cancel/re-run, or quarantine. Record each job and reservation ID.
4. For assigned work, wait for terminal GitHub state or use the approved
   emergency-stop policy. Preserve runner/job correlation.
5. Reconcile local Agent state after restart. A stale or fenced Agent must not
   perform destructive process actions.
6. Confirm runner removal from authoritative GitHub inventory. Unknown or
   unavailable inventory means rollback is blocked/quarantined.
7. Confirm terminal job state, removal evidence, reservation satisfaction, and
   zero occupied v2 slots before changing workflow routing.
8. Deploy or select the exact rollback Worker/Gates/Client revisions recorded
   in the manifest. Do not use floating `main` or an unverified deployment.
9. Switch the consumer workflow back to the rollback routing generation.
10. Re-enable v1 only after the authority barrier is restored and the rollback
    manifest records actual SHAs and deployment IDs.

## Abort conditions

Stop the procedure and keep v2 fenced if any of these occur:

- Cloudflare quota or Worker errors continue;
- runner inventory is unknown or still shows a v2 runner;
- a reservation/slot has no unambiguous owner;
- workflow provenance, Worker deployment ID, or rollback SHA is missing;
- a retry storm or repeated launchd restart is observed.

## Verification record

Record only non-secret evidence:

| Check | Result | Evidence |
|---|---|---|
| v2 claims stopped | `TBD` | Worker/admin observation |
| v2 sessions fenced | `TBD` | session/reconciliation output |
| queued/leased disposition complete | `TBD` | job/reservation ledger |
| assigned jobs terminal | `TBD` | GitHub job IDs |
| runner removal authoritative | `TBD` | GitHub runner observation |
| v2 slots zero occupied | `TBD` | RunnerPool state |
| rollback revisions verified | `TBD` | release manifest |
| v1 routing restored | `TBD` | workflow commit/run evidence |

Never paste tokens, private keys, credential proofs, or raw JIT configuration
into the record.
