# CI Scope v2 — Client Handoff Report

Дата: 2026-08-13  
Репозиторий: `/Users/daliys/Daliys/Swift/CI Scope`

Этот документ предназначен для агента, который объединяет CI Scope client, CI-Scope-Web и ci-gates.

## Baseline

- Baseline commit до client work: `d9c345af304a6963e0c496e7357fb3ade9063c5f`.
- Client changes пока не закоммичены.
- Legacy broker и существующие Python changes не переписывались.
- Legacy broker пока нельзя удалять: удаление возможно только после общего cross-repository cutover barrier и rollback evidence.

## Что готово

### 1. Go Agent foundation

Каталог: `agent/`

Реализовано:

- state-owner loop с состояниями `STARTING`, `RECOVERING`, `READY`, `PAUSED_NO_CONTROL`, `DRAINING`, `DORMANT`, `RECOVERY_BLOCKED`;
- typed operation results и stale-result fencing;
- local owner lock через `flock`;
- local epoch fencing;
- recovery decision list: `keep_running`, `observe`, `stop_orphan`, `remove_registration`, `release_unassigned`, `block_recovery`;
- SQLite WAL store;
- durable intent journal с `fsync`;
- JSONL journal как migration/recovery fallback;
- fake control plane с lost-response и idempotency tests;
- environment allowlist;
- фильтрация `SSH_AUTH_SOCK`, `GITHUB_TOKEN`, `GH_TOKEN` и backend/API tokens;
- bounded/collision-resistant runner name generation;
- runner process group через `Setpgid`;
- redacted JIT diagnostics;
- PID/start time/process group/executable/runner identity model;
- allowlisted workspace roots;
- symlink-safe cleanup и ownership marker.

Основные файлы:

- `agent/state.go`
- `agent/owner.go`
- `agent/journal.go`
- `agent/store_sqlite.go`
- `agent/schema.sql`
- `agent/recovery.go`
- `agent/process.go`
- `agent/path.go`
- `agent/runner.go`
- `agent/controlplane.go`
- `agent/env.go`

SQLite schema предусматривает таблицы:

- `agent_metadata`;
- `machine_state`;
- `intents`;
- `runner_processes`;
- `pending_requests`.

### 2. Watchdog

Каталог: `agent/watchdog/`

Реализовано:

- monotonic health sequence;
- допустимые state transitions;
- sleep/wake grace period;
- restart-storm guard;
- observable restart counter;
- `RECOVERY_BLOCKED` decision;
- отсутствие доступа к Agent SQLite;
- отсутствие сигналов runner process group.

Файлы:

- `agent/watchdog/health.go`
- `agent/watchdog/grace.go`
- `agent/watchdog/storm.go`
- `agent/watchdog/launchd/com.forkhorizon.ci-scope.agent.plist.tmpl`
- `agent/watchdog/launchd/com.forkhorizon.ci-scope.watchdog.plist.tmpl`

### 3. Swift protocol bridge

Файлы:

- `CI Scope/V2ClientBridge.swift`
- `CI Scope/V2ClientBridgeTests.swift`

Реализовано:

- request/response envelopes;
- protocol version `2`;
- `requestId`;
- SHA-256 `payloadHash`;
- session context: `machineId`, `bootId`, `agentInstanceId`, `sessionId`, `sessionEpoch`;
- fencing context: `localOwnerEpoch`, `sessionEpoch`, `fencingToken`, `runnerInstanceId`;
- response fields: `operationId`, `serverRevision`, `outcome`, `retryAfterMs`;
- outcomes: `accepted`, `succeeded`, `rejected`, `retryable`, `ambiguous`;
- status projection:
  - `processAlive`;
  - `schedulerHealthy`;
  - `controlLeaseActive`;
  - `serverConnected`;
  - `readyToClaim`;
  - `draining`;
  - `recoveryBlocked`;
  - `projectionLagging`;
- control commands:
  - `acquireControlLease`;
  - `renewControlLease`;
  - `resume`;
  - `drain`;
  - `emergencyStop`;
  - `status`;
- Unix socket mode `0600`;
- socket owner UID and peer UID validation;
- bounded newline-delimited JSON frames;
- read/write timeout;
- request/response ID matching;
- malformed-frame protection.

`readyToClaim` вычисляется только при выполнении всех безопасных условий: process alive, scheduler healthy, active control lease, server connected, не draining, не recovery blocked и projection не lagging.

### 4. Swift app lifecycle

Файл: `CI Scope/CI_ScopeApp.swift`

Normal Quit больше не вызывает `uninstallLaunchAgent()` и не останавливает broker/active runner. Active CI job должен продолжать работу после закрытия UI. Drain и emergency stop должны выполняться через Agent control lease.

## Проверки

Успешно выполнены:

```text
Go Agent:
go test ./...
go test -race ./...
go vet ./...

Watchdog:
go test ./...
go test -race ./...

launchd:
plutil -lint для обоих plist templates

Swift:
xcodebuild build CODE_SIGNING_ALLOWED=NO
swiftc XCTest typecheck

Python:
52 passed, 1 skipped

git diff --check:
passed
```

В Xcode-проекте нет отдельного XCTest target. Swift tests typecheck-ятся, но пока не запускаются через `xcodebuild test`.

## Что ещё должен сделать интеграционный агент

### Agent runtime

Foundation готов, но отсутствуют production runtime-компоненты:

- Agent executable/main;
- реальный HTTP/TLS server client;
- `openSession` и machine enrollment;
- heartbeat;
- claim/reservation protocol;
- prepare/start/stop/release requests;
- reconciliation;
- bounded worker orchestration;
- Unix socket listener/server.

### Runner lifecycle

Нужно подключить реальные операции:

- JIT preparation и ACK/start;
- runner registration;
- process observation;
- process start-time inspection;
- runner ID reconciliation;
- graceful stop;
- process-group termination;
- runner registration removal;
- safe cleanup;
- ambiguous-result handling.

Lost HTTP response не должен приводить к повторному external side effect.

### Swift UI

`V2ClientBridge.swift` сейчас является protocol/security layer и ещё не подключён полноценно к UI. Нужно интегрировать его с:

- `ContentView`;
- `RunnerFleetViewModel`;
- `RunnersView`;
- settings/control UI.

Нужно добавить реальные UI actions для acquire/renew/resume/drain/emergency stop/status. Broker JSON не должен оставаться authority для v2 scheduling state.

### Credentials and packaging

Нужно реализовать:

- Keychain machine credential;
- Keychain ACL для signed Agent identity;
- отсутствие secrets в launchd environment;
- signed Agent binary;
- signed Watchdog binary;
- update path;
- rollback path;
- launchd installer;
- restart counter persistence/observability.

### Cross-repository integration

Client ожидает совместимость с Web/gates по следующим полям и семантике:

- protocol version;
- machine enrollment;
- session/epoch/fencing;
- reservation и runner lifecycle;
- routing generation;
- trust class;
- runner group и labels;
- migration disposition для legacy v1 state.

До согласования этих контрактов нельзя включать реальные claims.

### Canary/release validation

Остаются:

- local two-Agent contention;
- stale Agent fencing;
- network partition;
- lost response для всех mutating operations;
- sleep/wake;
- low disk;
- UI crash;
- watchdog restart storm;
- PID reuse;
- symlink escape;
- 24-hour canary soak;
- rollback drill;
- release manifest с SHA всех трёх репозиториев.

## Важные ограничения

Не смешивать с client v2 changes следующие pre-existing dirty files:

- `.gitignore`;
- `CI Scope/Broker/CI Scope Broker`;
- `CLAUDE.md`;
- `tests/broker/test_broker.py`.

Также не считать текущий `backend/` production server authority: это исторический Python/FastAPI prototype.

## Итоговый статус

```text
Client Phase 0 — completed
Client Phase 1 — completed
Client Phase 2 — completed
Client Phase 3 — completed
Client Phase 4 — completed
Client Phase 5 — not completed
```

Главная следующая задача: подключить production Agent runtime к server protocol, подключить Swift UI к Unix socket и провести совместный canary с Web и gates.
