# CI Scope v2 — integration status

Дата проверки: 2026-08-15

Этот файл фиксирует фактическое состояние трёх worktree после cross-repository
аудита. Handoff-отчёты не считаются доказательством готовности, если код,
конфигурация или тесты говорят обратное.

## Baseline

| Репозиторий | HEAD на момент проверки | Состояние |
|---|---|---|
| `CI-Scope` | `d9c345af304a6963e0c496e7357fb3ade9063c5f` | dirty; client/agent V2 changes не закоммичены |
| `CI-Scope-Web` | `5d60e94f2ee66a3711233d01dcaa6788bff2d440` | dirty; V2 Worker changes не закоммичены |
| `ci-gates` | `8b216020f179766ecaa65e19be14342cc6072648` | dirty only by local integration-policy change; V2 implementation commit из handoff: `f10f47b1dab83473c0e55111979cd92e1b501a8c` |

## Что соединено сейчас

- Server protocol остаётся источником wire shape: `identity`, `fenceToken`,
  `accepted|completed|rejected|retry|ambiguous` и dedicated credential-proof
  header.
- Go Agent получил HTTPS transport и типы фактического Worker envelope в
  `agent/protocol.go` и `agent/controlplane_http.go`. Транспорт проверяет
  protocol/request ID/outcome и не повторяет side effect сам.
- Go Agent получил локальный Unix-socket runtime: mode `0600`, peer UID
  validation, bounded newline frames, control lease, status/lifecycle commands
  и fail-closed emergency stop. Runner controller теперь подключён к
  reservation.prepare JIT response, process fencing и lifecycle commands.
- Go Agent получил runnable `cmd/ci-scope-agent` bootstrap с strict env
  validation, owner lock, one-time enrollment, fenced `session.open` →
  `session.activate` → heartbeat → close; staging setup описан в
  `agent/AGENT_BOOTSTRAP.md`.
- Swift UI получил lease-gated `V2ClientStatusAdapter`, status-панель,
  settings/control actions и автоматическое чтение non-secret Agent session
  descriptor; legacy broker остаётся authority по умолчанию до explicit opt-in.
- Worker получил credential-checked `GET /api/ci/v2/operations/{id}`, fail-closed
  webhook routing из `CI_SCOPE_V2_GITHUB_WEBHOOK_ROUTING` и обязательную V2 env
  validation.
- Gates получили reusable routing-validation job, явный fail вместо skipped,
  SHA enforcement для v2 production/canary и release-manifest enforcement.
- Swift local bridge теперь fail-closed по protocol version, session/fencing
  epoch и response context; добавлены stale-fence tests.
- Worker deployment config теперь требует три V2 secret/binding значения, а
  shared CORS allowlist включает оба V2 credential headers.
- Disposable remote V2 deployment выполнен под `forkhorizon` с generated test
  secrets; D1 migrations применены, `GET /api/ci/v2/health` и admin auth
  проверены remotely. Последний deployment ID:
  `3c4b0ea4-b4e5-4704-bc08-15448bbf6fb7`.
- Полный disposable Agent smoke пройден remotely: issuer-authenticated
  enrollment/credential persistence, session open/activate, heartbeat, close;
  operation-status route также проверен как downstream route (`401` при
  отсутствующем credential, не shadow `404`).
- Production Agent bootstrap получил macOS Keychain fallback для device
  credential и shadow token; launchd renderer пишет только non-secret
  configuration и прошёл `plutil -lint`.
- Production Cloudflare topology provisioned separately from staging: Worker
  `ci-scope-web-production`, D1
  `ci-scope-web-production-db` (`9196960f-1021-4938-a5e6-1785219ebe0b`), all
  five remote migrations, seven required secrets, and deployment
  `ca01f8d6-aae6-442f-ad67-1fbbdcd08357`; production health returned `200`.
- Web now contains an injectable Web Crypto RS256 GitHub App/JIT client that
  is disabled unless `CI_SCOPE_V2_GITHUB_APP_ENABLED` is exactly `true`; raw
  JIT config crosses only the authenticated one-time reservation.prepare
  response and is never persisted.
- Agent now contains a fail-closed runner process-controller interface with
  ownership/fencing validation for claim, prepare, start, stop, release and
  observation; no real process side effect is enabled by default.
- Swift now exposes an explicit `legacyBroker` / `v2ReadOnly` /
  `v2Authority` state and a lease-gated mutation adapter; legacy authority
  remains the default.
- GitHub App is created and installed for `ForkHorizon` (App ID `4592685`,
  installation ID `153671069`); selected runner group
  `ci-scope-v2-canary` exists for `CI-Scope`, with no runner registered yet.
- Gates policy больше не принимает uppercase/64-character SHA, расходящиеся с
  release-manifest contract.

## Проверки

- Swift: shared `CI Scope` and `CI ScopeTests` schemes are checked in;
  `xcodebuild -scheme CI Scope ... build CODE_SIGNING_ALLOWED=NO` succeeds and
  `xcodebuild -scheme CI ScopeTests ... test` runs a real XCTest bundle with
  4/4 passed. Existing bridge and adapter regression sources remain in the
  app's synchronized source tree; the new target covers the release-critical
  protocol/lease/readiness paths.
- Go Agent: `go test ./...`, `go test -race ./...`, `go vet ./...`,
  `go mod verify` и Darwin arm64 build — passed.
- Web: `pnpm test` — 21/21; `pnpm run typecheck`; `pnpm run build`; Wrangler
  types/startup/dry-run; remote Worker deploy and V2 health smoke — passed.
- Gates: `pytest` 918 passed, 1 skipped, 357 subtests, `compileall` и
  `git diff --check` — passed.

## Local quota-free hardening completed

- Web #0050: expired request identities are retained as replay tombstones;
  reuse after TTL returns `idempotency_expired` instead of a new mutation.
- Web #0051: GitHub runner observation is a persisted intent resumed by the
  Durable Object alarm, so slow external calls do not hold the mutation path.
- Web #0052: outbox alarm delivery uses the D1 projection adapter when wired,
  persists delivered/retry/dead-letter transitions, and leaves rows pending
  when no adapter exists. Restart/fault tests cover the path.
- Agent #0053/#0054: restart/shutdown reconciliation, bounded stop/removal/
  release recovery, retry preservation, and watchdog launchd validation guard
  are covered by crash/restart, race, vet, and launchd tests.
- Gates #0055: release enforcement now requires independently supplied,
  verified workflow SHA and Worker deployment evidence; unresolved fixtures
  fail closed. Gates rollback instructions are documented separately.
- Integration artifacts: `CI_SCOPE_V2_RELEASE_MANIFEST.md` remains draft and
  activation-blocked; `CI_SCOPE_V2_ROLLBACK_RUNBOOK.md` documents the authority
  barrier and abort conditions.
- Local release checks: unresolved external provenance is rejected with exit 2;
  rendered launchd plist validation passes; secret-pattern scans across all
  three repositories found no private-key or token-shaped values; production
  Agent and watchdog launchd services are not loaded on this Mac.

## Что ещё блокирует end-to-end/cutover

1. Production secret storage/topology is provisioned and the server JIT path
   plus real fenced runner controller are wired, but production JIT remains
   disabled; legacy broker remains the factual runtime/scheduling owner until
   a live canary proves the new path.
2. Swift mutating control actions, normal-quit drain and automatic Agent
   discovery are implemented, but authority migration remains explicit opt-in.
3. Runner API observers, outbox delivery and D1 projection now have local
   durable/fault coverage, but still need live canary/soak evidence.
4. Нет production generation barrier/state-adoption ledger, release manifest с
   фактическими deployment IDs, live trust fixture, canary/soak и rollback
   evidence.
5. Gates validator уже fail-closed для v2, но production consumer migration,
   actual SHA manifest и organization-level trust evidence ещё отсутствуют.
6. Cloudflare production Worker is now deployed through Wrangler and health
   verified, but this is infrastructure readiness rather than production
   cutover: custom routing, GitHub JIT side effects, canary evidence and
   rollback are still missing.

Итог: contract/transport foundations стали совместимее и проверяются, но
release green и production cutover пока **не достигнуты**.
