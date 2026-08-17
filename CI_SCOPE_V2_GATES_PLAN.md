# CI Scope v2 — проектный план workflow и ci-gates

## Назначение

Этот файл является планом для отдельного репозитория ForkHorizon/ci-gates:

~~~
/Users/daliys/ci-gates
~~~

Он определяет только workflow-facing contract: как workflows выбирают runner group/labels, как gates запускаются в ephemeral workspace, как сохраняется progress marker и как проверяется trust policy. Server control plane описан в [CI_SCOPE_V2_SERVER_PLAN.md](CI_SCOPE_V2_SERVER_PLAN.md), macOS Agent — в [CI_SCOPE_V2_CLIENT_PLAN.md](CI_SCOPE_V2_CLIENT_PLAN.md), общая миграция — в [CI_SCOPE_V2_CROSS_REPOSITORY_PLAN.md](CI_SCOPE_V2_CROSS_REPOSITORY_PLAN.md).

## Граница ответственности

ci-gates владеет:

- reusable/generated workflows;
- runs-on group + labels + routing generation contract;
- совместимостью gate scripts с ephemeral workspace;
- сохранением additive ::ci-scope-progress:: JSON contract;
- canary workflows и negative trust fixtures;
- workflow pinning и release manifest inputs;
- tests, которые доказывают отсутствие v1/v2 double eligibility в consumer workflows.

ci-gates не владеет:

- scheduler logic;
- claim/reservation/lease state;
- GitHub App token или webhook ingress;
- local Agent lifecycle;
- Durable Object/D1;
- runner process creation/cleanup;
- admin or emergency stop.

## Фактическая исходная точка

Исторически CI Scope consumer использует generated workflow и external ci-gates reference с floating main/gates-ref: main. Текущие workflows используют self-hosted macOS labels и pull_request paths. Это нельзя принимать как готовую trusted routing policy.

Перед изменениями зафиксировать:

- current ci-gates baseline SHA;
- список consumers и reusable workflow versions;
- generated workflow files в CI Scope;
- current runs-on values;
- gate input contract;
- progress marker consumers;
- required CI checks и branch protections;
- dirty state отдельного ci-gates checkout.

Подписка на main означает, что release manifest может стать невоспроизводимым после изменения ci-gates. Production release pin-ит workflow/gate SHA или явно блокирует activation.

## Routing contract v2

Workflow v2 выбирает полную структуру:

~~~
{
  "generation": "v2",
  "group": "ci-scope-v2-trusted",
  "labels": ["self-hosted", "macOS", "ARM64", "ci-scope-v2"]
}
~~~

Необходимо подтвердить реальным GitHub canary, что reusable workflow корректно формирует runs-on: group + labels. Если текущий input принимает только labels, вводятся additive inputs runner-group и runner-labels; v1 defaults не меняются до canary.

Routing generation:

- является explicit field в workflow-facing contract;
- совпадает с server-approved routing configuration;
- не передаётся как произвольный label без group/access checks;
- не допускает v1/v2 eligibility overlap;
- pin-ится в release manifest вместе с workflow SHA, group ID/name и activation time.

Один label не является scheduler lock или trust boundary. GitHub group/labels только ограничивают placement. Server generation barrier остаётся обязательным.

## Trusted workflow predicate

Trusted pool допускает job только когда workflow contract и source identity удовлетворяют policy:

- approved repository ID;
- approved head repository ID;
- allowed event type;
- trusted ref/head SHA;
- approved workflow file/source SHA;
- approved reusable workflow origin;
- actor/branch policy;
- known routing generation;
- complete webhook/queue metadata.

Deny/quarantine по умолчанию для:

- external fork pull_request;
- неподтверждённого pull_request_target;
- workflow checkout с untrusted head SHA;
- external reusable workflow;
- rerun с неизвестной source identity;
- merge queue/multiple-repository source без fixture;
- missing event fields;
- workflow, который использует floating ref там, где требуется reproducibility.

Labels trusted недостаточны. Trust policy должна быть одновременно в workflow configuration, organization runner group restrictions и server predicate.

## Gate execution contract

Каждый gate работает в ephemeral workspace и не предполагает:

- постоянный user home;
- установленный local broker;
- writable repository вне workspace;
- доступ к interactive credentials;
- наличие persistent runner registration;
- доступ к GitHub App private key или machine credential.

Gate scripts обязаны:

- использовать allowlisted workspace paths;
- корректно работать на clean checkout;
- не делать destructive cleanup вне workspace;
- соблюдать bounded logs/output;
- возвращать стабильные exit codes;
- не скрывать cancelled/infrastructure result как linter verdict;
- сохранять progress event без secrets и untrusted raw values.

## Progress marker contract

Существующий additive marker сохраняется:

~~~
::ci-scope-progress:: {"step":"lint","current":1,"total":7,"detail":"..."}
~~~

Contract:

- step обязателен;
- current/total optional, но если присутствуют — non-negative bounded integers;
- detail redacted и ограничен по размеру;
- marker не содержит token, path с secret, raw payload или user credential;
- изменение schema требует version field и consumer tests;
- marker failure не меняет scheduler state и не является terminal job conclusion.

ci-gates не должен предполагать, что progress marker означает runner assignment или GitHub terminal status. Это только job-facing observability.

## Что должно измениться в ci-gates

### 1. Reusable workflow inputs

Добавить backward-compatible inputs:

- runner-group;
- runner-labels;
- routing-generation;
- workflow-contract-version;
- optional trust fixture mode для canary only.

Сделать validation:

- group и labels не пустые;
- v2 generation требует dedicated group;
- v1/v2 routing inputs не смешиваются;
- unknown generation fail-closed;
- production workflow не принимает произвольный group от untrusted input.

### 2. Generated workflows

Для каждого generated workflow:

- явно указать group + labels;
- pin-ить ci-gates and related reusable workflow SHA;
- не менять v1 defaults в том же PR, что v2 implementation;
- добавить v2 canary workflow с отдельным group/label;
- добавить negative fixture external fork/untrusted source;
- добавить same-label concurrent jobs;
- добавить rerun and requeue fixtures;
- зафиксировать workflow SHA в release manifest.

### 3. Gate scripts

Для scripts/linter и остальных gates:

- проверить clean ephemeral workspace;
- сохранить current changed/all mode semantics;
- проверить max output and annotation escaping;
- проверить progress marker compatibility;
- проверить cancellation/infrastructure distinction;
- не читать Agent/D1/server state;
- не отправлять secrets в annotations/logs;
- добавить tests для workspace missing, symlink/path escape и bounded output.

### 4. Trust-facing checks

Добавить structural checks, которые блокируют activation если:

- external fork workflow направлен в trusted group;
- pull_request_target checkout-ит untrusted head;
- production workflow использует floating main вместо pinned SHA;
- group/labels не соответствуют routing generation;
- workflow source SHA отсутствует в manifest;
- reusable workflow origin не approved;
- v1 and v2 routing fields появляются одновременно.

## Этапы реализации

### Gates Phase 0 — contract inventory

- Зафиксировать baseline SHA и consumer list.
- Собрать current runs-on/gates-ref/main references.
- Проверить required CI checks и branch protection.
- Зафиксировать progress marker consumers и version.
- Утвердить group/labels/generation JSON contract.
- Составить trust fixtures для fork/PR/target/reusable/rerun/merge queue.
- Не менять production routing.

### Gates Phase 1 — additive contract

- Добавить inputs и schema validation без изменения v1 defaults.
- Добавить unit tests для group/labels/generation.
- Добавить progress marker version/size/redaction tests.
- Добавить workflow lint/structural checks.
- Pin internal action/reusable references в canary only.

### Gates Phase 2 — canary workflows

- Создать canary workflow в dedicated v2 runner group.
- Запустить несколько same-label jobs.
- Проверить queued/in_progress/requeue/completed/rerun fixtures.
- Проверить external fork denied/not eligible.
- Проверить отсутствующий metadata deny-by-default.
- Проверить no side effect on production workflows.

### Gates Phase 3 — consumer migration

- Обновлять consumer workflows по одному репозиторию.
- Для каждого consumer фиксировать repo SHA, workflow SHA, ci-gates SHA, group/labels, routing generation и rollback target.
- Запрещать смешение v1/v2 eligibility.
- Проверять GitHub API-shaped proof до activation.
- Не использовать floating main в production release manifest.

### Gates Phase 4 — cutover/rollback

- Перевести v1 workflow consumers в drain согласно cross-repository ledger.
- Не пытаться routing existing queued job изменением workflow file.
- Для queued old jobs использовать drain или approved cancel/re-run policy.
- Rollback выполняется через generation barrier, не только git revert.
- После soak удалить legacy workflow inputs/paths отдельным PR.

## Тестовая стратегия

Обязательны:

- schema/property tests для routing object;
- v1 backward compatibility;
- v2 group+labels contract;
- generation mismatch fail-closed;
- same-label concurrent jobs;
- queued -> in_progress -> queued -> completed;
- rerun identity fixtures;
- duplicate/delayed webhook consumer fixtures;
- external fork/pull_request_target negative cases;
- reusable workflow source validation;
- floating ref detection;
- progress marker schema/redaction/bounds;
- ephemeral clean workspace;
- symlink/path escape;
- cancellation vs linter verdict;
- bounded output/annotation escaping;
- release manifest consistency.

## Handoff и DoD

ci-gates передаёт server/client:

- pinned workflow and gate SHAs;
- exact routing JSON contract;
- trust predicate fixtures and negative results;
- progress marker schema/version;
- consumer migration matrix rows;
- canary evidence and rollback target.

DoD наступает только когда:

1. v1 defaults остаются совместимы до activation;
2. v2 workflows имеют dedicated group + labels + generation;
3. production refs reproducible;
4. untrusted source не eligible для trusted group;
5. progress markers не содержат secrets и не маскируют infrastructure failure;
6. server generation barrier и client Agent protocol совпадают;
7. все affected repository checks terminal и green.
