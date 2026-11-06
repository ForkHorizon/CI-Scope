# CI Scope v2 — проектный план клиентской части

## Назначение

Этот файл является планом только для репозитория ForkHorizon/CI-Scope:

~~~
/Users/daliys/Daliys/Swift/CI Scope
~~~

Он декомпозирует общий план CI Scope v2 и предназначен для агента, который будет менять macOS-клиент, локальный Agent/Watchdog и packaging. Общие правила ownership, routing generation, migration barrier и rollback находятся в [CI_SCOPE_V2_ARCHITECTURE_PLAN.md](CI_SCOPE_V2_ARCHITECTURE_PLAN.md) и [CI_SCOPE_V2_CROSS_REPOSITORY_PLAN.md](CI_SCOPE_V2_CROSS_REPOSITORY_PLAN.md).

Этот документ не разрешает commit, push, deployment или удаление legacy. Сначала выполняется Phase 0 общего плана и фиксируется baseline checkout.

## Граница ответственности

Клиент владеет:

- Swift UI и отображением server/local state;
- Go Agent с режимами agent и watchdog;
- local state-owner lock и local epoch fencing;
- локальной SQLite для process facts и durable intents;
- launchd definitions, signed binary, update/install path;
- Unix domain socket и UI control lease;
- созданием, запуском, наблюдением и безопасным cleanup runner process group;
- временным legacy Python broker до подтверждённого cutover.

Клиент не владеет:

- GitHub queue, assignment или terminal job conclusion;
- server capacity, pool routing, trust class и runner group policy;
- Durable Object/D1 state;
- webhook authority;
- dashboard projection или admin scheduler decision.

## Фактическая исходная точка

В текущем checkout есть Swift UI, LocalBrokerService, launchd installer и legacy broker. Граф кода показывает отдельные пути чтения broker-state.json, runner snapshot и broker status; это process/status integration, а не v2 control-plane protocol. В worktree уже есть чужие изменения в:

~~~
CI Scope/Broker/CI Scope Broker
tests/broker/test_broker.py
~~~

Их нельзя смешивать с v2. Legacy broker остаётся действующим owner до общего cutover barrier.

Критические исходные риски, которые клиентский план обязан закрыть:

1. broker может быть жив по PID, но scheduler/state writer — stale;
2. текущие process facts и server facts смешиваются через JSON snapshot;
3. JIT config может попадать в argv и inherited environment;
4. старый Agent может проснуться после fencing и сделать destructive local effect;
5. UI lifecycle не должен останавливать active GitHub job при crash;
6. PID без start time/process group не доказывает ownership;
7. cleanup не должен следовать symlink или удалять чужой workspace.

## Что должно измениться

### 1. Go Agent

Создать state-owner loop, который единолично изменяет локальное состояние. Network, filesystem preparation и subprocess operations выполняются bounded workers и возвращают typed result; worker не мутирует state напрямую.

Состояния Agent:

~~~
STARTING → RECOVERING → READY ↔ PAUSED_NO_CONTROL
                    ↘ DRAINING → DORMANT
                    ↘ RECOVERY_BLOCKED
~~~

READY разрешает claims только когда одновременно подтверждены local lock, active control lease, server session, successful reconciliation и отсутствие recovery block. PAUSED_NO_CONTROL и DRAINING запрещают новые claims, но не завершают active runner автоматически.

Каждый внешний result содержит operation ID, expected transition/local epoch и server session epoch. Stale result отбрасывается; при необходимости запускается reconciliation.

### 2. Local ownership и fencing

До открытия server session Agent получает crash-safe exclusive lock на machine. Второй процесс разрешён только в diagnostic mode без claims и destructive effects.

Перед каждым destructive effect повторно проверяются:

~~~
local owner epoch
lock ownership
agentInstanceId
sessionEpoch/fencing token
runnerInstanceId
~~~

Fenced Agent не может stop, delete, cleanup, release или запустить новый runner. Если JIT config уже выдан, его нельзя отозвать локальным CAS: Agent переводит intent в CANCEL_PENDING, не запускает новый side effect и передаёт runner/name/ID на server reconciliation. Это residual risk, а не ложная exactly-once гарантия.

### 3. Local SQLite и intents

SQLite в WAL mode хранит:

- machineId, bootId, agentInstanceId;
- current sessionId, sessionEpoch, server revision;
- slots и reservations как durable replica;
- local owner epoch и control lease state;
- preparation/dispatch intents;
- runner ID/name/attempt, PID, process start time, process group;
- pending requests, request payload hash и idempotency keys;
- reconciliation result и recovery diagnostics.

Перед каждым side effect сохраняется intent:

~~~
prepare JIT
create directory
spawn process
SIGTERM/SIGKILL
remove runner registration
cleanup workspace
release reservation
~~~

После crash intent не повторяется вслепую. Agent сначала наблюдает фактический process/GitHub result, затем применяет explicit action list: keep_running, observe, stop_orphan, remove_registration, release_unassigned или block_recovery.

### 4. Runner process lifecycle

Runner запускается в отдельной process group и allowlisted рабочей директории. Ownership доказывается комбинацией PID, process start time, process group, executable identity и runnerInstanceId; ps alone запрещён.

Runner name генерируется детерминированно, ограничивается GitHub-compatible длиной/символами и имеет collision-resistant suffix. Name является correlation hint, не identity: server mapping обязан использовать runner ID, group/org, preparation и session data.

JIT config:

- принимается только для текущей session/epoch/reservation;
- не пишется в logs, UI, D1 или обычные snapshots;
- удаляется после ACK/spawn/expiry;
- никогда не передаётся через диагностические логи;
- считается краткоживущей secret capability.

GitHub runner contract использует run.sh --jitconfig, поэтому production выбирает dedicated CI account либо документирует accepted same-user argv exposure. Нельзя одновременно обещать, что same-user job гарантированно не увидит capability.

### 5. Swift UI и Unix socket

Swift UI перестаёт быть scheduler и не читает server-owned state через эвристический merge. Он обращается к Agent через user-owned socket с mode 0600 и peer UID verification.

Команды:

~~~
acquireControlLease(appInstanceId)
renewControlLease(appInstanceId, controlToken)
resume(appInstanceId, controlToken)
drain(appInstanceId, controlToken)
emergencyStop(appInstanceId, controlToken, requestId)
status()
~~~

UI показывает раздельно:

~~~
processAlive
schedulerHealthy
controlLeaseActive
serverConnected
readyToClaim
draining
recoveryBlocked
projectionLagging
~~~

UI crash/force quit только истекает control lease: active runner продолжает работу, новые claims запрещены. Normal Quit делает bounded drain ACK и не ждёт окончания CI job. Emergency stop требует действующий control lease, проверяет ownership перед остановкой и не объявляет GitHub job terminal.

Все production-critical gh calls удаляются из Agent path. Оставшиеся Swift developer diagnostics мигрируют отдельно и не должны менять server scheduling state.

### 6. Watchdog и launchd

Agent и Watchdog устанавливаются отдельными LaunchAgents из одного подписанного бинарника. Watchdog:

- проверяет scheduler health sequence state-owner loop, а не только PID;
- учитывает sleep/wake grace;
- после подтверждённого stall завершает только Agent;
- не пишет Agent SQLite;
- не освобождает reservation;
- не сигналит runner process group;
- оставляет recovery новому Agent.

Нужны restart-storm guard, наблюдаемый restart counter и operator-visible RECOVERY_BLOCKED, если Agent не может пройти recovery.

### 7. Machine credential и environment

Agent получает machine-bound device credential только из macOS Keychain. Credential не хранится в launchd plist, environment, command line или logs. Keychain ACL привязывается к подписанной Agent identity.

Runner получает минимальный allowlisted environment:

- нет SSH_AUTH_SOCK;
- нет interactive credentials и unrelated user variables;
- explicit HOME, TMPDIR, workspace, tool cache и DerivedData roots;
- нет GitHub App private key, installation token или постоянного user credential;
- Agent не использует sudo.

Если Agent и job работают под одним user, это явно residual risk. Production fleet должна использовать dedicated non-admin CI account, если это возможно операционно.

## Этапы реализации в клиентском репозитории

### Client Phase 0 — baseline и preflight

- Зафиксировать commit SHA, dirty files и packaging baseline.
- Не трогать перечисленные чужие broker/test изменения.
- Подтвердить server API protocol range, enrollment flow и routing generation.
- Получить реальные JIT redacted fixtures и runner version compatibility.
- Зафиксировать macOS profile, Keychain ACL, allowed roots и disk budget.
- Подтвердить, что current UI/broker path не будет одновременно owner с v2 Agent.

### Client Phase 1 — fake control plane

- Реализовать local SQLite schema и migrations.
- Реализовать owner lock, local epoch и state-owner loop.
- Реализовать fake control-plane client с lost response/stale epoch/error cases.
- Реализовать process observation без запуска real runner.

### Client Phase 2 — runner lifecycle

- Реализовать intent-before-effect для directory/spawn/stop/cleanup.
- Подключить JIT preparation/config ACK/start protocol.
- Реализовать process group, PID reuse check и symlink-safe cleanup.
- Реализовать ambiguous preparation и cancellation/reconciliation path.

### Client Phase 3 — Watchdog/launchd/packaging

- Добавить state-owner health sequence и sleep/wake handling.
- Установить Agent/Watchdog launchd definitions.
- Подписать бинарник и проверить update/rollback path.
- Проверить отсутствие inherited secrets и restart storm.

### Client Phase 4 — Swift UI migration

- Перевести status/control на Unix socket.
- Добавить explicit control lease, resume, drain и emergency stop.
- Убрать broker JSON как authority; оставить redacted diagnostics только как projection.
- Отделить process/scheduler/control/server/projection states в UI.

### Client Phase 5 — canary и cutover

- Пройти fake fault matrix, race detector и local two-Agent contention.
- Установить подписанный Agent на одну canary machine.
- Проверить restart, network partition, sleep/wake, UI crash, stale Agent и low disk.
- После общего v1/v2 barrier перевести fleet по одной машине.
- Удалять legacy broker отдельным PR только после cross-repository cutover.

## Тесты и acceptance

Обязательны:

- Go race detector и fake clock;
- SQLite corruption/ambiguous state → RECOVERY_BLOCKED;
- два Agent конкурируют за lock;
- fenced Agent не делает destructive effect;
- PID reuse и process-group ownership;
- crash после каждого persisted intent;
- lost response openSession, claim, prepare, start, stop;
- hung HTTP/TLS/subprocess и bounded worker saturation;
- Keychain ACL/environment sanitization;
- path traversal/symlink escape/allowlisted roots;
- low-disk блокирует новые claims, но не убивает active runner;
- UI crash запрещает claims, но не active jobs;
- normal Quit/resume/drain/emergency stop;
- watchdog не убивает runner process group;
- 24-hour canary soak без duplicate live runner/stuck recovery.

## Handoff и критерии готовности

Клиентский проект передаёт серверу:

- versioned Agent protocol и release manifest;
- machine enrollment/rotation evidence;
- runner lifecycle event schema;
- exact local state/intent schema;
- canary logs без secrets;
- список поддерживаемых Agent protocol versions.

Client DoD наступает только когда общий cross-repository plan подтверждает один active authority, а не только когда Swift/Go локальные тесты зелёные.
