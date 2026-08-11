# CI Scope

## Logging

Both the local broker and the GUI app write structured JSON-lines logs (one JSON object per line — grep/jq-friendly). Added 2026-07-19 for stress-test debugging; previously there was no logging at all.

### File locations

| Component | Full log (INFO+) | Errors only (WARN+) |
|---|---|---|
| Broker (Python) | `~/Library/Logs/CI Scope/Broker/broker.jsonl` | `~/Library/Logs/CI Scope/Broker/broker-errors.jsonl` |
| GUI app (Swift) | `~/Library/Logs/CI Scope/App/app.jsonl` | `~/Library/Logs/CI Scope/App/app-errors.jsonl` |

Check `broker-errors.jsonl` / `app-errors.jsonl` first when debugging — small, signal-only files instead of the full firehose.

Also relevant, but not part of this structured logging system:
- `~/Library/Logs/CI Scope/Broker/{job-id}.log` — raw stdout of each individual JIT runner process (pruned after 14 days, `CI_SCOPE_LOG_RETENTION_DAYS`).
- `~/Library/Logs/DiagnosticReports/CI Scope-*.ips` — macOS's own crash reporter output for hard Swift crashes (force-unwrap, trap). Not custom-built; the app only catches uncaught NSExceptions itself (see `AppLogger.crash`).
- `~/Library/Application Support/CI Scope/Broker/broker-state.json` — current live state snapshot (queue/actives/profiles), not a log.

### Format

```json
{"ts": "2026-07-19T12:56:51.98Z", "level": "INFO", "component": "broker", "event": "job.dispatch", "msg": "...", "context": {"jobId": "...", "repo": "...", "pid": 123}}
```
`level` is one of `DEBUG`/`INFO`/`WARN`/`ERROR`/`CRASH`. `context` is optional, omitted when empty.

### Viewing

```
tail -f ~/Library/Logs/CI\ Scope/Broker/broker-errors.jsonl | jq .
tail -f ~/Library/Logs/CI\ Scope/App/app-errors.jsonl | jq .
grep '"jobId":"<id>"' ~/Library/Logs/CI\ Scope/Broker/broker.jsonl   # one job's full lifecycle
```

### Rotation

Size-based, 20MB per file × 5 backups (`.1` oldest-first) — bounded (~100MB per stream), not append-forever. Broker's caps are env-overridable: `CI_SCOPE_LOG_MAX_BYTES`, `CI_SCOPE_LOG_BACKUPS`, `CI_SCOPE_LOG_LEVEL`.

### Source

- Broker: `CI Scope/Broker/CI Scope Broker` (Python, stdlib `logging` + `RotatingFileHandler`, `JsonLogFormatter`, `log_event()` helper).
- App: `CI Scope/AppLogger.swift` (`AppLogger.shared`, mirrors every line to `os.Logger` too). Instrumented centrally in `ShellClient.run` — covers every `gh`/`git`/`launchctl` call the app makes — plus app launch/quit and uncaught-exception handling in `CI_ScopeApp.swift`.

### Gotcha

The **running broker** is a deployed copy at `~/Library/Application Support/CI Scope/Broker/CI Scope Broker`, not the source file. Editing `CI Scope/Broker/CI Scope Broker` in the repo has no effect until the app redeploys it — **Settings → Install/Restart Broker**, or relaunching the app.
