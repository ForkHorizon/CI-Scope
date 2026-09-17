# Unified checks baseline and migration matrix

Baseline captured 2026-09-06 from checked-in workflows and local repository
state. Scope is installed CI only; experimental scripts and generated runtime
data are excluded.

## Shared contract

- Consumer workflows call `ForkHorizon/ci-gates` reusable workflows at `main`.
- Normal consumers use self-hosted macOS ARM64 runners. SOMA uses `ci-scope`
  for five gates and `ci-scope-ai` for Slop Review; the canary advertises
  `ci-scope-v2` in its dedicated runner group.
- Pull requests, merge queues, manual dispatch, and weekly Monday schedules
  are enabled where shown below. Every workflow uses concurrency cancellation
  except the canary, which deliberately keeps both jobs.
- No workflow declares an explicit cache or mutates external services. The
  observable side effects are GitHub checks, summaries/artifacts from
  `ci-gates`, and local tool/build output. AI use is limited to Slop Review;
  the caller selects its model while `ci-gates` owns execution and prompt policy.

## SOMA pilot baseline

Repository: `ForkHorizon/Soma`  
Baseline SHA: [`a74f7112c21c1531142d755b7dd7a0ada0a3b048`](https://github.com/ForkHorizon/Soma/commit/a74f7112c21c1531142d755b7dd7a0ada0a3b048)

| Workflow | Check/adapter | Config and notable semantics | Latest successful run |
|---|---|---|---|
| Code Linter | `code-linter` | `.code-linter.json`; `all`/`changed` dispatch mode, otherwise `auto` | [33811707036](https://github.com/ForkHorizon/Soma/actions/runs/33811707036) |
| Swift Quality Gate | `swift-quality` | `.swift-quality-gate.json`; `run-build: false`; Swift format; dead code disabled | [33811707044](https://github.com/ForkHorizon/Soma/actions/runs/33811707044) |
| Swift Compile Gate | `swift-compile` | `.swift-compile-gate.json`; warnings and critical Swift-concurrency patterns fail | [33811707055](https://github.com/ForkHorizon/Soma/actions/runs/33811707055) |
| Python Quality Gate | `python-quality` | default gate config; repository Python quality | [33811707180](https://github.com/ForkHorizon/Soma/actions/runs/33811707180) |
| Go Quality Gate | `go-quality` | `working-directory: Soma/go_scanner`; repository Go quality | [33811707062](https://github.com/ForkHorizon/Soma/actions/runs/33811707062) |
| Slop Review | `slop-review` | no project config; `qwen3-coder:30b-a3b-q4_K_M` model; execution/advisory semantics owned by reusable workflow | [33811707060](https://github.com/ForkHorizon/Soma/actions/runs/33811707060) |

All six rows pin `gates-ref: main` and retain their existing concurrency
groups. Five use `self-hosted, macOS, ARM64, ci-scope`; Slop Review uses
`self-hosted, macOS, ARM64, ci-scope-ai`. `ci-scope-v2` is only used by the
separate CI Scope canary, not by the SOMA pilot. The unified
pilot must preserve these six checks and their required/advisory policy; the
current repository does not encode that policy in workflow YAML, so required
status must be confirmed from branch protection before cutover.

## Migration matrix

| Project | Installed checks/workflows | Config or adapter inputs | Runner | Cache / side effects / AI | Status |
|---|---|---|---|---|---|
| `ForkHorizon/Soma` | Code Linter; Swift Quality; Swift Compile; Python; Go; Slop Review | `.code-linter.json`, `.swift-quality-gate.json`, `.swift-compile-gate.json`; Go subdirectory | macOS ARM64, `ci-scope` (five gates), `ci-scope-ai` (Slop Review) | No declared cache; build/format/lint output; Slop Review AI | **Pilot baseline captured; T01 ready for manifest work** |
| `ForkHorizon/CI-Scope` | Code Linter; Swift Quality; Swift Compile; Python; Slop Review; v2 Canary | `.code-linter.json`; Swift gates; Swift Quality skips duplicate build; canary pins gates SHA and v2 routing inputs | macOS ARM64, `ci-scope`; canary group `ci-scope-v2-canary` | No declared cache; canary intentionally creates two same-label jobs; Slop Review AI | **Legacy migration after SOMA; canary is infrastructure evidence, not a product check** |
| `ForkHorizon/WebSite` | Code Linter; Web Quality; Slop Review | `.code-linter.json`; Web Quality `duplication-threshold: 3` | macOS ARM64, `ci-scope`, `ci-scope-v2` | No declared cache; web quality output; Slop Review AI | **Pending adapter and baseline run evidence** |
| `ForkHorizon/CI-Scope-Web` | No `.github/workflows` in checkout | `package.json`: test, typecheck, build; Wrangler Worker/VPS deployment config | N/A (local/deployment checks are not consumer workflows) | Deployment and database migrations are side effects; no AI workflow | **Exclude from first consumer migration; define server validation separately** |
| `ForkHorizon/ci-gates` | Reusable gate workflows plus self-check/routing workflows | Gate implementations and reusable workflow contracts | Workflow-specific; consumer runner requirements belong to callers | Produces checks/artifacts; Slop Review may invoke AI; no consumer cache declaration | **Shared adapter source; pin SHA during migration** |

## Cutover records still required

1. Confirm branch-protection required versus advisory semantics for each
   consumer; workflow YAML alone does not establish this.
2. Pin the `ci-gates` commit and record the unified workflow commit for every
   migration row.
3. Add at least five comparable SOMA legacy/unified run pairs, including cold
   and warm cache observations, AI time, cancellation, rollback, and orphan
   checks before changing required statuses.
