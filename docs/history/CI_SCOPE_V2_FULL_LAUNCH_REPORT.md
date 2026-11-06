# CI Scope v2 — отчёт до полного запуска

Дата: 2026-08-14

Обновление: 2026-08-16. VPS control plane deployed at
`https://ci.forkhorizon.com`. A controlled `ForkHorizon/CI-Scope` canary
started a real Code Linter job successfully (`95194055597`); the second job was
cancelled because the canary had one VPS slot. The canary exposed cleanup and
webhook projection issues. The Agent/Web fixes are implemented, covered by
regression tests, and deployed: missing GitHub `preparation_id` is accepted,
stale-session observer recovery can use a replacement active session, and
terminal observer intents complete after a reservation is already terminal.
Controlled recovery cancelled the orphan reservation, freed the VPS slot, and
completed all deferred observer intents. GitHub App effects are disabled again.
Full cutover remains blocked by soak, rollback drill, and immutable release/PR
acceptance.

The follow-up controlled recovery on 2026-08-16 found and fixed one additional
protocol bug: the stale-reservation recovery branch returned a `retry` response
with a payload, which violates the V2 response contract and surfaced as HTTP
400. The response now carries the required retry error without a payload, with
a regression assertion in the Web suite. The cancelled recovery run was
cleaned up; the VPS slot is available, GitHub App effects are disabled, and no
GitHub disposable runners remain.

The clean repeat canary then passed on run `31968552186` (head
`b05632db8bf475385ec8c9b0afbfa2d928369a77`): jobs `95217329078` and
`95217329112` both succeeded, terminal webhook projection completed, runners
were removed before the slot returned to `available`, and the outbox remained
empty. GitHub App effects are disabled again after the canary. A second
controlled wrapper canary passed on run `31969159516` (head
`b05632db8bf475385ec8c9b0afbfa2d928369a77`): jobs `95218749756` and
`95218749852` both succeeded, and a queued job was recovered after restarting
the Agent. The live run exposed a transient orphan-listener risk; the checked-
in wrapper now kills the complete runner process group and its synthetic
termination test passes. Remaining gates are soak, rollback drill, and
immutable release/PR acceptance.

## Итоговый статус

Сейчас готов интегрированный кодовый вертикальный слой: protocol/state
primitives, runnable Go Agent bootstrap with enrollment/session-open/
heartbeat/close, fenced Unix socket control runtime, one-time GitHub App JIT
delivery из authoritative Worker reservation path, Swift lease-gated
authority с автоматическим discovery Agent session, gates release enforcement,
remote staging deploy и отдельный production Worker с production D1,
migrations, secrets и health check. Полный production cutover по-прежнему
невозможен до реального runner canary, soak и rollback evidence.

Последняя staging-проверка также прошла полный disposable Agent lifecycle:
issuer-authenticated enrollment/one-time credential, `session.open`,
`session.activate`, heartbeat, Unix-socket runtime startup и graceful close.

| Область | Статус | Что это означает |
|---|---|---|
| Protocol/state contracts | Yellow | Go/Swift/Worker envelopes и fencing проверены, golden fixtures ещё нужны |
| Swift UI + Agent runtime | Yellow | Runner lifecycle, fencing, socket control, UI lease actions и automatic session discovery есть; controlled canary passed four real jobs total, wrapper lifecycle fix is covered locally, but packaging/install and soak remain |
| VPS/Worker production effects | Yellow | JIT, observer recovery and release are wired; clean live repeat canary and projection passed, but soak/rollback remain |
| Gates routing | Yellow | Fail-closed validator and routing checks pass; pinned canary fix is in draft PR #66 and is not merged |
| Migration/rollback/operations | Red | Нет ledger, generation barrier, soak и drill |

Зелёные unit/type/build проверки не равны end-to-end readiness.

## Что обязательно сделать

### P0 — Зафиксировать release baseline

Владелец: integration/release owner.

- Разделить текущие V2 изменения и существующие dirty-файлы во всех трёх
  worktree.
- Зафиксировать фактические commits, workflow SHA, Worker deployment ID,
  `ci-gates` SHA, DO schema version, D1 projection version и routing generation.
- Назначить одного webhook mutation owner, одного scheduler authority и одного
  rollback owner.
- Утвердить финальные payload fixtures: enrollment, session, reservation,
  prepare, runner lifecycle, webhook assignment и terminal evidence.

Выход: reproducible release manifest без floating production refs.

### P1 — Доделать production server

Владелец: `CI-Scope-Web`.

- Подключить реальный GitHub App client: JIT config теперь вызывается из
  authoritative `reservation.prepare`; raw config возвращается только один раз
  в authenticated response и не попадает в persisted state. Runner
  registration/removal и наблюдение runner/job ещё требуют live canary.
- Подключить outbox delivery и D1 projection к production topology.
- Подключить reconciliation scheduler и GitHub-shaped observers.
- Реализовать operation status/read model для `accepted` и `ambiguous` операций.
  Локальный Worker route и credential-checked DO read уже добавлены; disposable
  remote deployment/evidence проверены, production-shaped side effects ещё нет.
- Завершить routing/trust configuration: organization, repository, head
  repository, event, ref/SHA, workflow source, runner group и labels.
- Реализовать/проверить v1/v2 generation barrier в authoritative DO.
- Production namespace, D1, migrations, secrets и health уже provisioned;
  остаются rotation/alerts, custom route/DNS/TLS и operational verification.
- Проверить DO storage migration, restart, malformed state и rollback без
  destructive schema rollback.

Выход: server может безопасно принять session/claim/lifecycle requests и
выполнить реальные side effects с persist-before-effect, fencing и
reconciliation.

### P2 — Доделать Agent и runner lifecycle

Владелец: `CI-Scope` Agent.

- Создать production executable/main и конфигурацию запуска. Staging command
  `agent/cmd/ci-scope-agent`, strict env parser, macOS Keychain source и
  non-secret launchd plist renderer уже добавлены; подписанный packaging,
  Watchdog binary и фактическая установка ещё нужны. Production Keychain
  bootstrap helper уже provisioned локально.
- Подключить уже добавленный HTTPS transport к enrollment, `session.open`,
  heartbeat и close. Local lifecycle client уже добавлен и покрыт TLS tests;
  remote Worker health smoke и полный disposable credential/enrollment/session
  lifecycle пройдены; production packaging и persistent credential source ещё нужны.
- Реализовать persistent machine credential reference из Keychain.
- Реализовать heartbeat, session renewal, stale/fenced handling и recovery.
- Реализовать claim/reservation/renew/prepare/start/stop/release flow. Go
  Agent принимает одноразовый JIT response, пишет временный config с mode
  `0600`, запускает и наблюдает процесс с PID/start-time/process-group
  fencing и clean release.
- Передавать серверный opaque `runnerInstanceId` и полный immutable
  `runnerCorrelation`.
- Реализовать JIT preparation ACK, process observation, start-time/PID/group
  checks, runner registration/removal и safe cleanup.
- Добавить Unix socket listener с mode `0600`, peer UID validation, bounded
  frames, request ID matching и control lease. Локальный listener/control
  slice уже добавлен и протестирован; остаётся подключить его к executable и
  реальному lifecycle.
- Завершить retries для `accepted`, `retry`, `ambiguous`, `stale_session` и
  `fenced_session`; lost response не должен повторять внешний side effect.

Выход: Agent самостоятельно переживает restart/network partition/sleep-wake и
не допускает destructive effect от fenced или stale epoch.

### P3 — Перевести Swift UI на Agent

Владелец: `CI-Scope` Swift UI.

- Подключить bridge к `ContentView`, `RunnerFleetViewModel`, `RunnersView` и
  settings/control UI. Bridge автоматически обнаруживает live Agent через
  локальный non-secret session descriptor и остаётся fail-closed по socket.
- Реализовать status, acquire/renew/resume/drain/emergency-stop actions — эти
  lease-gated actions теперь есть; фактический authority cutover остаётся
  explicit opt-in до canary.
- Удалить broker JSON как authority для V2 scheduling state; legacy broker
  оставить только до отдельного cutover PR.
- На normal quit делать bounded drain/control-lease flow, не останавливая
  подтверждённые active jobs.
- Добавить настоящий XCTest target и выполнять Swift tests через `xcodebuild
  test`, а не только compile.
- Подготовить signed Agent/Watchdog binaries, Keychain ACL, launchd installer,
  update path и rollback path.

Выход: UI отображает Agent-owned state и не может обходить server/Agent
ownership rules.

### P4 — Завершить gates и consumer migration

Владелец: `ci-gates` + consumer workflow owner.

- Создать production release manifest и migration matrix с реальными SHA.
- Pin-ить production `gates-ref` на commit SHA; `main` оставить только для
  backward-compatible development path.
- Перевести выбранный canary workflow на exact
  `group + labels + routing-generation + workflow-contract-version`.
- Сделать invalid routing явным failed check, а не только skipped job.
  Local reusable-workflow validator уже добавлен; нужна проверка в реальных
  consumer repositories.
- Запустить structural trust checks в реальном consumer workflow, а не только в
  unit tests.
- Проверить GitHub runner group restrictions, fork deny и
  `pull_request_target` negative fixtures в организации.
- GitHub App создан/установлен: App ID `4592685`, installation ID `153671069`;
  selected runner group `ci-scope-v2-canary` создан для `CI-Scope`, но JIT
  runner side effects и реальный runner пока не подключены.
- Убрать persistent credential/workspace leaks в Unity и Slop Review paths.

Выход: один canary workflow имеет одну eligible routing domain и reproducible
gate revision.

### P5 — Провести интеграционные fault tests

Владельцы: все три репозитория; coordinator — integration owner.

Обязательно проверить:

- golden JSON/hash fixtures между TypeScript, Go и Swift;
- duplicate request ID и duplicate event с новым request ID;
- lost response после server commit;
- stale session/epoch/fence и delayed old-session events;
- two-Agent contention и fenced Agent destructive-effect denial;
- assignment до config/start/observed;
- stop до start и `runner.stopped` без автоматического slot release;
- runner registration/removal reconciliation;
- webhook duplicate/out-of-order/replay/quarantine;
- GitHub terminal event раньше local process stop;
- DO restart, D1 outage, outbox quota, malformed persisted state;
- low disk, PID reuse, symlink escape, UI crash, watchdog restart storm;
- unknown protocol/trust/routing — deny, без fallback dispatch.

Выход: результаты сохранены как CI evidence, а не только как локальный test
output.

### P6 — Canary, migration и cutover

Владелец: release/operations owner.

1. Deploy server в disposable staging namespace с generated test secrets —
   выполнено: `forkhorizon`, deployment `3c4b0ea4-b4e5-4704-bc08-15448bbf6fb7`.
   Production namespace также provisioned: Worker `ci-scope-web-production`,
   D1 `ci-scope-web-production-db`, deployment
   `ca01f8d6-aae6-442f-ad67-1fbbdcd08357`; health check passed after the
   fail-closed GitHub App/JIT client and Agent process-controller seam landed.
2. Установить dormant Agent на одну canary machine.
3. Запустить один pinned v2 workflow с двумя same-label jobs.
4. Доказать единственного scheduler owner и отсутствие v1/v2 overlap.
5. Прогнать 24-часовой soak с restart, network partition и sleep/wake.
6. Заполнить state-adoption ledger для queued/leased/assigned v1 jobs.
7. Перевести v1 в `DRAIN_ONLY`, закрыть старые assignments и только затем
   включить v2 claims.
8. Провести rollback drill: fence v2, drain/quarantine jobs, cleanup runners,
   восстановить authority barrier и только потом вернуть v1.
9. Расширять fleet по одной машине за раз.
10. Удалять legacy broker/endpoints отдельными PR после soak и rollback evidence.

Выход: canary и rollback доказаны фактическими run/job/deployment evidence.

## Финальный release gate

Запуск разрешён только если одновременно выполнено всё:

- client, server и gates DoD закрыты;
- actual SHA/deployment IDs внесены в release manifest;
- protocol fixtures одинаково проходят в Go/TypeScript/Swift;
- один webhook mutation owner и один scheduler authority доказаны;
- все legacy queued/leased/assigned states имеют disposition;
- trust negative fixtures green;
- production secrets/rotation/alerts проверены;
- canary выдержал 24 часа;
- rollback drill успешен;
- все affected checks трёх репозиториев terminal and green.

До выполнения этих условий нельзя объявлять production cutover или удалять
legacy broker.

## Текущая команда запуска

На текущем состоянии проверены только локальные foundations:

- Swift build — passed (есть Swift 6 concurrency warnings в текущем Swift 5
  режиме; отдельного XCTest target нет);
- Go tests/race/vet/module verify — passed;
- Web 21/21 tests, typecheck/build, Wrangler types/startup/dry-run — passed;
- Gates 908 tests, discovery 65/65, compileall — passed.
- Remote Worker `https://forkhorizon.ci-scope-web.workers.dev`: admin auth и
  `/api/ci/v2/health` — `200`; DO reports one available slot.
- Production Worker `https://ci-scope-web-production.ci-scope-web.workers.dev`:
  deployment `fb6f6c28-a8f5-46ed-8bd2-2e4337e42960`; `/api/ci/v2/health` —
  `200`; one available slot, zero active sessions.

Это подтверждает качество подготовленного слоя, но не закрывает P1–P6.
