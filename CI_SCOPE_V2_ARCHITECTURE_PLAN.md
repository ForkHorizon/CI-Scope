# CI Scope v2 — master architecture index

## Статус

Это master-файл общего архитектурного контракта. Детали реализации и проектные задачи вынесены в отдельные планы:

1. [CI_SCOPE_V2_CLIENT_PLAN.md](CI_SCOPE_V2_CLIENT_PLAN.md) — macOS client, Swift UI, Go Agent/Watchdog, launchd, local SQLite и runner process lifecycle.
2. [CI_SCOPE_V2_SERVER_PLAN.md](CI_SCOPE_V2_SERVER_PLAN.md) — Cloudflare Worker, RunnerPool Durable Object, D1, GitHub App, webhook ingress, reconciliation и admin API.
3. [CI_SCOPE_V2_GATES_PLAN.md](CI_SCOPE_V2_GATES_PLAN.md) — ForkHorizon/ci-gates, workflow routing, runs-on contract, trust-facing checks и progress marker.
4. [CI_SCOPE_V2_CROSS_REPOSITORY_PLAN.md](CI_SCOPE_V2_CROSS_REPOSITORY_PLAN.md) — общие protocol/generation contracts, migration matrix, state adoption, cutover и rollback.
5. [CI_SCOPE_V2_VPS_MIGRATION_PLAN.md](CI_SCOPE_V2_VPS_MIGRATION_PLAN.md) — перенос production control plane с Cloudflare Worker/DO/D1 на собственный VPS.

Master-файл не является разрешением на implementation, commit, push, deploy или удаление legacy. Каждый проектный агент сначала проходит общий Phase 0 и работает только в своём репозитории.

## Цель

CI Scope v2 должен управлять ephemeral organization-level GitHub Actions runners на 2–10 trusted macOS machines при:

- одинаковых labels у нескольких jobs;
- duplicate/delayed/lost webhook deliveries;
- потере HTTP response после external side effect;
- рестарте UI, Agent, Watchdog, Worker или DO;
- network partition, sleep/wake, reboot и partially written local state;
- постепенной миграции трёх репозиториев без double dispatch.

Trusted jobs выполняются native на macOS. External fork/untrusted code не допускается в trusted pool. Native process separation не является malicious-code sandbox; это residual risk, который зафиксирован в client/server plans.

## Неподвижные архитектурные факты

CI Scope — capacity/reservation scheduler, а не окончательный GitHub job scheduler:

1. наблюдает queue/events;
2. резервирует capacity slot;
3. создаёт JIT runner;
4. запускает его локально.

GitHub сам выбирает queued job среди совместимых group + labels. Lease/reservation не является доказательством assignment. Terminal conclusion принадлежит GitHub и подтверждается webhook/reconciliation, а не local runner exit.

Внешние side effects не обещают exactly-once. Используются persist-before-effect, idempotency, fencing, CAS, ambiguous state и reconciliation.

## Ownership contract

| State | Единственный authority |
|---|---|
| pool/routing/generation | RunnerPool DO |
| machine session/epoch/slot/reservation/fence | RunnerPool DO |
| GitHub assignment/conclusion | GitHub, normalized in DO |
| runner PID/process group/directory | local Agent |
| local intents/retries | Agent SQLite |
| UI control lease | Agent |
| dashboard/history/audit | D1 projection |
| workflow routing declaration | ci-gates/consumer workflow |

D1 никогда не принимает scheduler decision. Agent heartbeat может сообщать observed health, но не увеличивает server-approved capacity, trust class или labels.

## Обязательные invariants

- Один githubJobKey имеет не более одного active owning scheduler.
- v1/v2 active routing domains не пересекаются; generation ambiguity блокирует claim.
- Один machine имеет не более одного current session epoch.
- Старый/fenced epoch не может heartbeat, claim, renew, release, stop или cleanup ownership нового epoch.
- У slot не более одного live runner instance.
- Lost response не вызывает blind повтор external side effect.
- GITHUB_ASSIGNED job не возвращается в queue из-за local timeout.
- Terminal GitHub state sticky для той же подтверждённой attempt.
- Webhook dedup не считается applied transition до состояния APPLIED или QUARANTINED.
- D1 lag/outage/replay не меняет scheduler decisions до storage budget.
- Outbox/task scheduler bounded, fair и operator-visible при poison/retry exhaustion.
- Ни один secret/JIT capability не попадает в logs, D1 или UI.
- Trusted pool deny-by-default для untrusted/fork/unknown source.
- Unknown routing, protocol или trust не вызывает fallback dispatch.
- Queued/leased/assigned jobs старого generation имеют explicit adopt/drain/cancel/re-run/quarantine disposition.

## Общий protocol contract

Каждый mutating request после session содержит protocolVersion, requestId, payload hash, machine/session identity и fencing fields. Response содержит operationId, serverRevision, outcome и retryAfterMs. Request после retention expiry возвращает idempotency_expired и не открывает новый external side effect.

Shared identity vocabulary:

~~~
machineId
bootId
agentInstanceId
sessionRequestId
sessionId
sessionEpoch
slotId
claimRequestId
reservationId
reservationToken
runnerInstanceId
preparationId
runnerAttempt
githubJobKey
runId/runAttempt
transitionSeq
eventId
routingGeneration
~~~

У каждого project plan есть собственный schema/implementation scope; cross-repository compatibility описан отдельно и обязателен для activation.

## Общая схема

~~~mermaid
flowchart LR
    UI["Swift CI Scope App"] -->|"Unix socket"| Agent["Go Agent"]
    Watchdog["Watchdog"] -->|"health only"| Agent
    Agent -->|"versioned API"| Worker["Cloudflare Worker"]
    Worker --> Pool["RunnerPool Durable Object"]
    Pool --> DO_SQL["Authoritative DO SQLite"]
    Pool --> D1["D1 projection/history"]
    Pool --> GitHub["GitHub API"]
    GitHub --> Worker
    Agent --> Runner["Ephemeral JIT Runner"]
    Dashboard["VPS dashboard"] --> Worker
~~~

## Правила распределения работы

### Client agent читает

- CI_SCOPE_V2_CLIENT_PLAN.md;
- общие invariants и API sections этого файла;
- cross-repository migration/rollback plan.

Он не меняет Worker, DO, D1 или ci-gates.

### Server agent читает

- CI_SCOPE_V2_SERVER_PLAN.md;
- общие ownership/invariants/API sections;
- cross-repository generation/migration plan.

Он не меняет Swift UI, local process code или gate scripts.

### Gates agent читает

- CI_SCOPE_V2_GATES_PLAN.md;
- trust/routing/progress contracts;
- cross-repository matrix and cutover barrier.

Он не реализует scheduler, claim, lease, webhook или local Agent.

## Unified phases

1. Phase 0: baseline, dirty-worktree freeze, topology, fixtures, API/schema/trust/ownership approval.
2. Phase 1: shadow server ingress and additive workflow/client contracts without runner side effects.
3. Phase 2: isolated GitHub App/runner-group canary.
4. Phase 3: Agent/Worker integration against fake then canary control plane.
5. Phase 4: one canary machine/workflow and 24-hour soak.
6. Phase 5: fleet rollout one machine/repository at a time.
7. Phase 6: v1 drain, queued-state disposition, v2 activation.
8. Phase 7: separate legacy removal PRs after soak and rollback evidence.

No project declares cutover alone.

## Release gate

Release green только когда:

- client, server и gates project DoD выполнены;
- compatibility/migration matrix заполнена фактическими SHAs;
- один webhook mutation owner и один scheduler authority доказаны;
- queued/leased/assigned state adoption закрыт;
- trust predicate и negative fixtures green;
- production route/DNS/TLS/D1/VPS boundary проверены live;
- rollback и break-glass recovery отрепетированы;
- required checks трёх repositories terminal and green.
