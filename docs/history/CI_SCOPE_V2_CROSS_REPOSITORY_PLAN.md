# CI Scope v2 — cross-repository migration and release plan

## Назначение

Этот файл не является планом отдельного runtime-проекта. Он владеет только связями между:

1. ForkHorizon/CI-Scope — Swift UI, Go Agent/Watchdog, local process lifecycle;
2. ForkHorizon/CI-Scope-Web — Worker, RunnerPool DO, D1, GitHub App и webhook control plane;
3. ForkHorizon/ci-gates — workflow/gates contract и progress marker.

Проектные инструкции находятся в [CI_SCOPE_V2_CLIENT_PLAN.md](CI_SCOPE_V2_CLIENT_PLAN.md), [CI_SCOPE_V2_SERVER_PLAN.md](CI_SCOPE_V2_SERVER_PLAN.md) и [CI_SCOPE_V2_GATES_PLAN.md](CI_SCOPE_V2_GATES_PLAN.md). Этот файл обязателен для manager/release agent, который координирует их независимо.

## Общий authority contract

Для каждого состояния существует один owner:

| State | Owner |
|---|---|
| pool/routing/generation | RunnerPool DO |
| machine session/epoch/slot/reservation/fence | RunnerPool DO |
| GitHub assignment/conclusion | GitHub, normalized in DO |
| runner PID/process group/directory | local Agent |
| local intents/retries | Agent SQLite |
| UI control lease | Agent |
| dashboard/history/audit | D1 projection |
| workflow routing declaration | ci-gates/consumer workflow |

Общие invariants:

- один githubJobKey не имеет более одного active owning scheduler;
- v1/v2 active routing domains не пересекаются;
- D1 не принимает claim/admin scheduler decisions;
- stale/fenced Agent не делает destructive local effect;
- GitHub terminal state не откатывается;
- неизвестный routing/trust/protocol не приводит к fallback dispatch;
- queued/leased/assigned old jobs имеют explicit disposition;
- JIT ambiguity не закрывается слепым повторным external side effect.

## Compatibility matrix

Каждый release manifest содержит:

~~~
CI-Scope repository SHA
CI-Scope-Web repository SHA
ci-gates repository SHA
Agent protocol range
Worker protocol range
DO schema version
D1 projection version
workflow routing generation
progress marker version
release manifest version
Worker deployment ID
GitHub App permission version
runner group ID/name
activation timestamp
rollback target
~~~

Production не использует floating main/gates-ref: main там, где требуется reproducibility. Если внешняя floating dependency остаётся, activation блокируется до её pinning или explicit risk acceptance.

## Migration matrix по репозиториям

Перед каждой фазой обновляется таблица:

| Repository | Workflow SHA | ci-gates SHA | Agent/Worker version | Routing generation | Group + labels | Owning scheduler | Cutover barrier | Rollback |
|---|---|---|---|---|---|---|---|---|
| CI-Scope | required | required | required | v1/v2 | required | v1/v2 | required | required |
| CI-Scope-Web | deployment SHA | n/a | Worker/DO | v1/v2 | n/a | v1/v2 | required | required |
| ci-gates | required | self | contract version | v1/v2 | contract | n/a | required | required |

До activation выполняется GitHub-shaped proof, что affected representative queued job имеет ровно одну eligible routing domain. Изменение workflow не переписывает уже созданный job.

## State adoption ledger

Legacy state нельзя молча «подхватить» новым DO. Для каждого класса записывается disposition:

| Legacy state | Allowed disposition | Required evidence |
|---|---|---|
| queued v1 job | drain или cancel/re-run | job IDs и routing proof |
| leased v1 job | drain, adopt или quarantine | lease owner/expiry |
| assigned v1 job | дождаться terminal или emergency policy | runner/job mapping |
| active v1 runner | cleanup после terminal | runner ID/status |
| stale broker | quarantine/recovery | local state + process proof |
| webhook dedup/event | migrate audit или replay via inbox | payload hash/lifecycle |
| retry record | migrate with next-attempt или expire | retry horizon |
| shared bearer | rotate/revoke | machine credential evidence |

No state adoption without payload hash, source revision, owner and operator-visible result.

## Webhook ownership switch

Перед activation проводится inventory:

- GitHub App webhooks;
- repository/org webhooks;
- legacy broker consumer;
- VPS/Worker consumer;
- v2 Worker ingress;
- webhook secrets and rotation window;
- delivery IDs and duplicate consumers.

На каждом generation только один consumer применяет authoritative transition. Shadow consumer может нормализовать и сравнивать events, но не claim, не create/delete runner и не освобождает capacity.

Switch order:

1. создать v2 ingress/quarantine без side effects;
2. проверить signature, routing, inbox lifecycle и alerting;
3. deploy server compatibility;
4. deploy dormant Agent;
5. deploy canary workflow contract;
6. activate one routing generation;
7. disable old mutation consumer;
8. сохранить old read-only/audit consumer до soak;
9. удалить old consumer отдельным PR.

## Phases

### Cross Phase 0 — freeze and evidence

- Зафиксировать baseline SHA всех трёх repos.
- Отдельно записать dirty files; не stash/overwrite автоматически.
- Утвердить ownership/state machines/API schemas/routing/trust predicate.
- Проверить Cloudflare route/DNS/TLS/VPS boundary и dedicated D1.
- Получить GitHub JIT, webhook, requeue и rerun fixtures.
- Получить current v1 metrics/incident fixtures.
- Утвердить release manifest и migration ledger.
- Утвердить rollback owner и break-glass path.

### Cross Phase 1 — shadow

- Server shadow ingress/D1 projection без runner side effects.
- Client fake control-plane compatibility.
- ci-gates additive contract и canary-only routing.
- Compare normalized events and authority; legacy v1 remains sole scheduler.
- Alerts on divergence, unknown routing, trust gap, webhook lag and storage budget.

### Cross Phase 2 — isolated canary

- Dedicated v2 group selected only for canary repository/workflow.
- One Agent opens session in v2 pool.
- One canary workflow uses pinned group/labels/generation.
- Check same-label jobs, requeue, rerun, terminal mapping, UI crash, network partition and sleep/wake.
- No external fork fixture reaches trusted pool.
- Run at least 24-hour soak and rollback drill.

### Cross Phase 3 — fleet rollout

- Add machines one at a time.
- Verify sessions/epochs/slots/duplicate/orphan runners/webhook lag.
- Keep v1/v2 eligibility disjoint.
- Update migration matrix per repository SHA.
- Keep legacy read-only until defined soak/rollback evidence exists.

### Cross Phase 4 — cutover

1. Set v1 scheduler to DRAIN_ONLY.
2. Stop v1 claims.
3. Resolve queued/leased/assigned v1 jobs by ledger.
4. Confirm no unresolved v1 authority or active registration.
5. Switch workflow generation/group/labels.
6. Activate v2 claims.
7. Observe soak.
8. Remove legacy endpoints and broker in separate changes.

## Rollback protocol

Rollback does not mean immediate v1 start.

1. Stop new v2 claims.
2. Fence v2 sessions for dispatch without killing confirmed assigned jobs.
3. Resolve queued/leased v2 jobs by drain or approved cancel/re-run policy.
4. Wait terminal active jobs or perform explicitly authorized emergency stop.
5. Reconcile/delete/quarantine orphan v2 runners.
6. Confirm no live v2 runner or unresolved ownership; otherwise rollback remains blocked/quarantined.
7. Switch workflow routing back to v1.
8. Re-enable v1 only after authority barrier is restored.
9. Publish rollback manifest with actual SHAs/config/deployment IDs.

If Worker/DO is unavailable, use documented break-glass or declare rollback blocked. Do not use D1 snapshot or blind runner-name delete as proof.

## Cross-repository tests

Required integrated tests:

- compatibility matrix and manifest consistency;
- server old/new Worker protocol window;
- Agent old/new Worker session;
- DO partially migrated schema;
- D1 outage/outbox quota;
- webhook duplicate/partial apply/replay;
- lost JIT response and fenced Agent;
- same-label concurrent jobs and requeue;
- job rerun identity;
- trust deny for fork/pull_request_target/reusable workflow;
- workflow floating ref detection;
- v1/v2 generation proof;
- queued-job cutover ledger;
- Worker/DO outage break-glass;
- 24-hour canary and fleet soak;
- all affected CI checks terminal and green.

## Release gate

Один проект не может объявить готовность самостоятельно. Release green только когда:

- client, server и gates DoD выполнены;
- migration matrix заполнена фактическими SHA;
- webhook owner и authority barrier доказаны;
- queued/leased/assigned state disposition закрыт;
- production topology live-проверена;
- rollback отрепетирован;
- required checks всех трёх repositories terminal and green.
