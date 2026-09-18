# CI Scope v2 — проектный план серверной части

## Назначение

Этот файл является планом только для репозитория ForkHorizon/CI-Scope-Web:

~~~
/Users/daliys/Daliys/Web/CI-Scope-Web
~~~

Он предназначен для агента, который будет строить Cloudflare Worker, RunnerPool Durable Object, D1 projection, GitHub App integration, webhook ingress, reconciliation и admin API. Клиентский work находится в [CI_SCOPE_V2_CLIENT_PLAN.md](CI_SCOPE_V2_CLIENT_PLAN.md), workflow/gates — в [CI_SCOPE_V2_GATES_PLAN.md](CI_SCOPE_V2_GATES_PLAN.md), общая миграция — в [CI_SCOPE_V2_CROSS_REPOSITORY_PLAN.md](CI_SCOPE_V2_CROSS_REPOSITORY_PLAN.md).

Документ не разрешает deployment или изменение production topology до Phase 0 evidence.

## Граница ответственности

Server project владеет:

- Cloudflare Worker routes и canonical control-plane origin;
- machine enrollment, per-machine credentials и revocation;
- GitHub App identity и installation token;
- versioned routing configuration;
- one RunnerPool Durable Object per coordination pool;
- authoritative server sessions, epochs, slots, reservations, runner instances и transitions;
- webhook durable inbox и routing/quarantine;
- GitHub API side effects и server reconciliation;
- D1 projection/history/outbox delivery;
- authenticated admin operations, audit и recovery states;
- public API schema, compatibility range и release manifest metadata.

Server project не владеет:

- PID/process group/runner directory facts;
- local lock или destructive local process effect;
- Swift UI lifecycle;
- workflow source code и gate implementation;
- GitHub job terminal truth — GitHub остаётся источником assignment/conclusion, server хранит authoritative normalized observation.

## Фактическая исходная точка

Текущая система содержит legacy D1-backed claim/heartbeat/webhook paths, shared bearer authentication и VPS-shaped adapter с локальным SQLite. Worker/DO v2 ещё не является фактическим authority. Перед изменениями проверить актуальные:

- Worker/Durable Object bindings и wrangler configuration;
- текущие D1 databases и их ownership;
- VPS TLS/SNI route и public endpoint;
- server/index adapter;
- migration helper и production schema;
- webhook subscriptions и secrets;
- current endpoint consumers из Swift broker.

Existing shared ForkHorizon database не становится production v2 projection автоматически. Dedicated CI Scope D1 и canonical Worker origin должны быть подтверждены live.

## Server state ownership

RunnerPool DO является единственным authority для:

- pool/routing configuration version;
- machine sessions/epochs;
- server-approved capacity and capability profile;
- slots/reservations/fencing tokens;
- runner instances;
- job observations and ownership mappings;
- request deduplication;
- webhook inbox/delivery lifecycle;
- transition log;
- scheduled tasks/outbox;
- reconciliation state.

D1 — только projection/history/audit. D1 lag, replay, outage или stale dashboard snapshot не могут принимать claim/admin scheduler decisions.

Agent reports observed facts. It cannot increase capacity, set trust class, select another pool, or release server ownership on its own.

## Authority и routing generation

Один DO сериализует только один pool. Для каждого githubJobKey server project обязан поддерживать invariant:

~~~
githubJobKey -> active routingGeneration -> owning scheduler -> poolKey
~~~

В production active owning scheduler только один. v1/v2 overlap блокируется routing configuration и explicit activation barrier. Если routing domains когда-либо пересекаются, нужен отдельный durable ingress ownership gate; D1 для этого не подходит.

Routing configuration хранит:

- installationId, organizationId, repositoryId;
- numeric runnerGroupId и expected immutable-at-version group name;
- allowed repository IDs;
- required capability labels;
- trust class;
- workflow/source policy;
- routing generation;
- activation/deactivation state.

Unknown, stale или ambiguous mapping не создаёт DO, reservation или runner. Rename, deletion, access drift или generation mismatch переводят pool в ROUTING_BLOCKED.

## Durable Object state machines

### Machine session

~~~
OPENING -> ACTIVE -> STALE -> FENCED
                  ↘ CLOSED
~~~

openSession idempotent по machineId + sessionRequestId + payload hash. Новый agentInstanceId создаёт следующий epoch и fences previous session. Старый request после нового epoch возвращает stale_open_request/stale_session согласно retained request record; он не создаёт ещё один неожиданный epoch.

STALE запрещает новые claims, но не меняет active GitHub assignment.

### Capacity slot

~~~
AVAILABLE -> RESERVED -> RUNNER_PREPARING -> RUNNER_REGISTERED
          -> GITHUB_ASSIGNED -> RELEASING -> AVAILABLE
                         ↘ RECOVERY_BLOCKED
~~~

Configured capacity хранится server-side. Heartbeat только уменьшает effective availability при unhealthy/low-disk state.

### Reservation

~~~
RESERVED -> PREPARING -> REGISTERED -> ASSIGNED -> SATISFIED
        ↘ EXPIRED_UNASSIGNED
        ↘ CANCEL_PENDING -> CANCELLED
        ↘ AMBIGUOUS
~~~

TTL не является доказательством, что runner не сможет принять job. После expiry сначала проверяется runner registration/assignment и создаётся cleanup barrier. Reservation возвращается в eligible queue только после подтверждения, что старый runner не примет job.

Reservation expectedJob является advisory queue hint, не обещанием, что GitHub назначит именно эту job.

### Runner instance

~~~
INTENT_RECORDED -> CONFIG_REQUESTED -> CONFIG_READY -> PROCESS_STARTING
                -> ONLINE_IDLE -> ASSIGNED -> EXITED -> REMOVED
                               ↘ STOPPING
                ↘ AMBIGUOUS -> RECONCILING
~~~

Runner correlation использует runnerId, runnerName, runnerGroupId, installation/org, preparationId, runnerAttempt, sessionEpoch и reservationToken. Name alone запрещён.

### GitHub job

~~~
QUEUED <-> IN_PROGRESS -> TERMINAL
~~~

Terminal state sticky только для подтверждённой job attempt. in_progress -> queued допускается только при reconciliation confirmation текущего GitHub state; delayed webhook alone не откатывает assignment. Новый rerun/run attempt получает identity только после подтверждения реального GitHub contract на fixtures.

## Worker API

Worker является stateless boundary:

- TLS and canonical hostname;
- schema/body validation;
- device envelope verification;
- routing configuration lookup;
- authentication request routing в target DO;
- webhook signature verification before JSON parsing;
- stable error/HTTP response mapping.

Worker не принимает claim decision вне DO и не читает D1 для claims. VPS adapter не имеет production scheduler mutation path; если он остаётся для dev, это enforced by separate credentials/configuration, а не convention.

Versioned routes:

~~~
POST /api/ci/v2/enrollment
POST /api/ci/v2/sessions/open
POST /api/ci/v2/sessions/{id}/heartbeat
POST /api/ci/v2/sessions/{id}/reconcile
POST /api/ci/v2/sessions/{id}/close
POST /api/ci/v2/claims
POST /api/ci/v2/reservations/{id}/renew
POST /api/ci/v2/reservations/{id}/prepare-runner
POST /api/ci/v2/runner-instances/{id}/config-ack
POST /api/ci/v2/runner-instances/{id}/started
POST /api/ci/v2/runner-instances/{id}/observed
POST /api/ci/v2/runner-instances/{id}/stop-requested
POST /api/ci/v2/runner-instances/{id}/stopped
POST /api/ci/v2/webhooks/github
GET  /api/ci/v2/operations/{id}
~~~

Каждый mutating request содержит protocolVersion, requestId, payload hash, server/agent identity и fencing fields. Response envelope содержит requestId, operationId, serverRevision, outcome и retryAfterMs. Нужно зафиксировать HTTP status mapping, max body size, auth rate limits, redacted error body и idempotency_expired behavior.

## Enrollment и secrets

GitHub App private key хранится только в Cloudflare secret storage. Installation token никогда не передаётся машине.

Enrollment:

1. одноразовый короткоживущий enrollment token;
2. binding к machine bootstrap intent/pool;
3. атомарная mark-used;
4. machine-bound random device credential;
5. server stores salted hash/metadata в target DO;
6. credential rotation/revocation с overlap window;
7. revoked credential не может открыть session, heartbeat или side effect.

Signed envelope содержит несекретные credentialId, poolIdentity и machineId. Произвольный poolKey из client request не выбирает authority.

Нужны tests против replay, payload substitution, revoked credential, duplicate enrollment, wrong pool, stale epoch и credential rotation.

## GitHub App и JIT side effects

В Phase 0 зафиксировать реальный organization JIT endpoint, permission manifest, runner group access, response/error fixtures и cleanup endpoint. Обязательные cases: 201, 404, 409, 422, 429, transient 5xx, lost response, group drift и rate-limit reset.

JIT preparation:

1. persist intent and operationVersion in DO SQLite;
2. create/reuse preparation by preparationId;
3. obtain short-lived installation token;
4. call organization generate-jitconfig with canonical runner name/group/labels;
5. apply result by CAS over operationVersion, sessionEpoch and reservationToken;
6. deliver sealed config only to matching Agent;
7. keep config only until runnerStarted/expiry;
8. never write config to D1, log or UI.

Fencing cannot revoke config already returned to old Agent. On session fencing preparation goes CANCEL_PENDING and reconciliation must find/delete/quarantine runner. New runnerAttempt forbidden until prior runner absence/removal is confirmed.

DO must never hold a logical lock across GitHub/D1 fetch. External result is success, terminal_error or ambiguous and always carries operationId/version/target aggregate.

## Webhook ingress и durable inbox

Signature is verified before parsing. Delivery is deduplicated by delivery ID plus source context and payload hash. Inbox lifecycle:

~~~
RECEIVED -> NORMALIZED -> APPLIED
                    ↘ RETRY_PENDING
                    ↘ QUARANTINED
~~~

Duplicate response returns stable lifecycle/result status, not only duplicate=true. A recorded delivery whose transition application failed must be retried by alarm; redelivery must not silently become no-op.

Inbox fields include deliveryId, payloadHash, event/action, source, installation/org/repository, receivedAt, attemptCount, nextAttemptAt, appliedAt and quarantine reason. Raw payload is bounded/redacted and never assumed safe for logs/UI.

Unknown routing/runner/group is durable quarantine + alert. If no target DO exists, ingress quarantine must have an explicit owner; D1 may be audit projection but cannot be the only correctness store during D1 outage.

Webhook is not an ordered command. Each transition records source, sourceObservedAt, githubUpdatedAt when available, delivery/synthetic observation ID, runAttempt and aggregate revision. Delayed queued/in_progress cannot rollback terminal state. runner_name without runnerId/group/preparation mapping is quarantine.

## Queue discovery и reconciliation

Queue discovery is a backstop, not an assumption. Phase 0 must prove API coverage for jobs inside in_progress workflow runs, pagination/cursors, installation visibility, rate limits and eventual consistency. Scanning only queued workflow runs is insufficient.

Server reconciliation must cover:

- runner online/offline/busy/absent;
- runnerId/name/group and actual assigned job;
- queued/in_progress/terminal job state;
- run attempt;
- orphan registrations;
- missing webhook transitions;
- stale preparations and cleanup barriers.

All reconciliation uses the same transition functions as webhook/RPC. It has per-installation rate budget, bounded pages, persisted cursor/next attempt, Retry-After handling and no tight loop during GitHub outage.

A runner deletion decision is never made from one stale list response. Recheck assignment and pool mapping; if ownership is ambiguous, keep capacity blocked and require reconciliation/operator recovery.

## D1 projection, outbox и task scheduler

Authoritative transition and outbox row are written in one DO SQLite transaction. D1 applies unique event IDs and aggregate-specific transition sequence; a global sequence across aggregates is not assumed.

Scheduled task fields:

~~~
taskId, taskType, aggregateKey, notBefore, attemptCount,
nextAttemptAt, leaseOwner, leaseExpiresAt, lastError, terminalState
~~~

One DO alarm dispatches bounded, fair batches. It must provide aggregate operation lock, per-installation rate budget, poison task isolation, bounded wall-clock budget, retry budget and rescheduling after downstream outage.

Set:

~~~
outboxRowsLimit
outboxBytesLimit
maxOutboxAge
projectionBacklogThreshold
~~~

On storage budget breach, new claims stop in DEGRADED_PROJECTION/recovery state while active GitHub jobs continue. Silent authoritative storage exhaustion is a release blocker.

Retention is separate for transition log, inbox/dedup, idempotency, outbox and quarantine. After expiry, request IDs return idempotency_expired and never reopen an external side effect.

## Admin и break-glass

Admin mutations route to authoritative DO and include authenticated operator identity, RBAC scope, expectedServerRevision, audit event and confirmation policy.

Commands include drain, revoke, emergencyStop, quarantine, repair, capacity change and routing activation. D1 dashboard snapshot cannot authorize them.

Break-glass must be defined for Worker/DO outage. It either blocks GitHub routing and uses a separately audited GitHub cleanup credential, or rollback is explicitly forbidden until control plane returns. Blind delete by name or D1 snapshot is forbidden.

## Server implementation phases

### Server Phase 0 — topology and contract preflight

- Recheck Worker route, Cloudflare hostname, DO binding, D1 ownership and VPS boundary.
- Inventory GitHub App/webhook subscriptions and all current consumers.
- Fix organization JIT endpoint/permissions/group access fixtures.
- Fix queue discovery API coverage and redacted webhook/rerun/requeue fixtures.
- Define machine credential enrollment/rotation/revocation.
- Define routing configuration source/version and activation barrier.
- Define DO schema migrations, D1 migration/backup/recovery and outbox quotas.
- Approve API wire contract and compatibility matrix.

### Server Phase 1 — shadow ingress

- Add Worker v2 routes and SQLite-backed RunnerPool DO.
- Ingest webhooks with no claims or GitHub side effects.
- Store inbox lifecycle and compare v1/v2 normalized transitions.
- Publish separate D1 v2 projection.
- Alert on divergence, quarantine, routing drift, webhook lag and reconciliation gaps.
- Keep legacy v1 as sole scheduler authority until activation barrier.

### Server Phase 2 — GitHub App/canary

- Create least-privilege GitHub App.
- Create dedicated v2 organization runner group.
- Validate numeric ID/name, selected repositories/workflows and trust policy.
- Run JIT preparation/reconciliation without production workflows.
- Exercise 409/422/429/ambiguous/lost response/orphan cleanup.
- Confirm runner ID and group mapping.

### Server Phase 3 — Agent integration

- Enable session/heartbeat/reconcile protocol against fake then canary Agent.
- Validate stale epoch, local owner and machine-bound credential.
- Validate runner lifecycle events and operation status endpoint.
- Run D1 outage, DO eviction, alarm retry, storage quota and reconciliation tests.

### Server Phase 4 — production canary

- Activate one canary pool/machine only after cross-repo generation barrier.
- Verify same-label assignment/requeue/rerun/terminal mapping.
- Verify no v1 eligibility overlap and no duplicate runner.
- Run 24-hour soak and rollback drill.

### Server Phase 5 — fleet/cutover

- Add machines one at a time.
- Stop v1 claims before switching workflows.
- Resolve v1 queued/leased/assigned jobs via adoption, drain, cancel/re-run or quarantine ledger.
- Confirm no unresolved v1 authority.
- Activate v2 generation and retain legacy read-only until soak.
- Remove legacy endpoints/claims in separate PR.

## Server tests and DoD

Required:

- deterministic state-machine/property tests;
- concurrent claims and slot conflicts;
- DO interleaving during mocked external I/O;
- request dedup and payload hash conflict;
- stale session/epoch/fence rejection;
- webhook inbox partial failure and replay;
- out-of-order requeue/rerun/terminal fixtures;
- lost JIT response and fenced-Agent capability;
- runner ID/name/group/preparation rebind;
- alarm at-least-once/fairness/starvation/poison task;
- D1 outage/projection lag/outbox quota;
- schema migration and partially migrated DO recovery;
- admin RBAC/revision/audit/break-glass;
- rate limits and bounded queue discovery;
- trusted/untrusted source predicate;
- API status/retry/expiry/redaction contract.

Server DoD требует доказать, что DO — authority, D1 — projection, v1/v2 не claim-ят одну routing domain, queued old jobs не теряются, active assignments переживают Agent outage, and rollback не требует destructive schema rollback.
