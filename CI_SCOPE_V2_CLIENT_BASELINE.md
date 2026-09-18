# CI Scope v2 client baseline

Captured 2026-08-13 before client implementation work.

## Checkout

- Repository: `CI Scope`
- Baseline commit: `d9c345af304a6963e0c496e7357fb3ade9063c5f`
- Current branch: `daliys/fix-jit-runner-affinity`
- Client target: `CI Scope.xcodeproj` / `CI Scope`
- Toolchain: Swift 6.3.3, Xcode 26.5 SDK, Go 1.26.4

## Preserved dirty files

These pre-existing changes are outside the v2 client implementation and must remain untouched:

- `.gitignore`
- `CI Scope/Broker/CI Scope Broker`
- `CLAUDE.md`
- `tests/broker/test_broker.py`
- untracked project plans, projectmem state, and graphify output

## Baseline checks

- `xcodebuild -project "CI Scope.xcodeproj" -scheme "CI Scope" -configuration Debug -derivedDataPath /tmp/ci-scope-derived build CODE_SIGNING_ALLOWED=NO`: passed
- `python3 -m pytest -q`: `52 passed, 1 skipped`

## Scope boundary

This baseline covers only the client repository. Server, gates, routing generation, webhook authority, and production cutover remain external dependencies described by the architecture and cross-repository plans.

