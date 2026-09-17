# CI Scope: единый запуск проверок — SOMA → ForkHorizon

## Цель и решения

Заменить отдельные GitHub jobs одной self-hosted job. Она один раз получает исходники и закреплённую версию `ci-gates`, читает проектный `.ci-scope.json`, запускает существующие проверки и публикует общий check `CI Scope / Checks`, подробный summary и artifacts.

Первый пилот — `ForkHorizon/Soma`; после его приёмки мигрируют остальные проекты ForkHorizon. Все текущие проверки, включая AI, входят в общий запуск. Время AI измеряется отдельно и не используется для оценки ускорения инфраструктуры. Оптимизация моделей и промптов — отдельная последующая задача.

Первая версия выполняется на одной машине. Распределённая очередь подзадач, отдельные GitHub Checks для каждой проверки и собственный Checks API не входят в первый этап. Исполнение не зависит от открытого окна CI Scope. Существующие алгоритмы, ограничения линтеров и required/advisory semantics сохраняются.

## Правило выполнения задач

Одна задача назначается одному агенту-исполнителю. После его результата запускается новый независимый агент-проверяющий, который самостоятельно изучает diff, связанные вызовы, требования, безопасность, отмену, cleanup и совместимость. При найденной проблеме проверяющий исправляет её и добавляет регрессионную проверку. После каждого исправления запускается ещё один новый проверяющий. Задача принимается только после проверки, не потребовавшей изменений. При недоступной инфраструктуре или неоднозначном контракте задача получает статус `blocked`, а не обход проверки.

Для каждой задачи сохраняются исполнитель, проверяющие, commit/diff, команды, результаты, найденные проблемы и итог `accepted` или `blocked`. Изменение общего контракта требует повторной проверки всех затронутых задач.

## Архитектура и контракты

`ci-gates` предоставляет Python stdlib executor:

```text
python3 <gates>/scripts/run-checks.py \
  --root <workspace> --config <manifest> --event <event> \
  --base <sha> --head <sha> --output <run-directory>
```

Он поддерживает `--validate-only`, запускает команды через массив аргументов, ограничивает обычную параллельность двумя процессами, учитывает зависимости и эксклюзивные ресурсы, выполняет AI последовательно, имеет bounded timeouts, отменяет дерево процессов и удаляет только файлы собственного запуска. Неизвестные проверки и произвольные shell-команды из manifest запрещены.

`.ci-scope.json` содержит версию формата, стабильные IDs проверок, типы из доверенного каталога, существующие config paths, рабочие каталоги, параметры, зависимости и события. Обязательность и разрешённые параметры задаёт trusted catalog. Для PR исполняется принятая base policy; candidate manifest валидируется отдельно. Нельзя получить зелёный запуск с пустым или неизвестным набором проверок.

Статусы: `queued`, `running`, `passed`, `failed`, `skipped`, `cancelled`, `timed_out`, `infra_error`. Отчёт содержит run/attempt, repository, base/head/checked SHA, gates version, manifest digest, preparation/execution/cleanup timings и AI timing. Выход ненулевой при ошибке обязательной проверки, конфигурации или инфраструктуры.

Артефакты: `events.jsonl`, `result.json`, ограниченные логи и GitHub summary. Существующие `::ci-scope-progress::` markers остаются наблюдаемостью и не являются источником terminal success.

## Задачи

### T01 — baseline и migration matrix

Составить для всех проектов ForkHorizon инвентаризацию активных workflows, команд, config, версий, required/advisory semantics, runner requirements, caches, side effects и AI. Зафиксировать SOMA baseline SHA/run links и матрицу `project → checks → adapters → migration status`. Учитывать только установленные CI-проверки, не экспериментальные скрипты.

### T02 — manifest и trusted catalog

Добавить `.ci-scope.json`, Python models, fixtures, resolver и `--validate-only`. Проверить версии, IDs, параметры, paths, symlink escape, dependencies, cycles и обязательный набор. Не разрешать manifest ослаблять trusted policy.

### T03 — executor и process lifecycle

Добавить bounded parallel execution, dependency/resource scheduling, sequential AI phase, per-check timeouts, process-group cancellation, isolated temp roots, cleanup ownership, partial reports and explicit skipped dependents. Проверить orphan process, hung child, cancellation, resource conflict, concurrent runs and report-write failure.

### T04 — SOMA adapters

Подключить Code Linter (changed/all и signature guard), Python (Ruff), Go (download/vet/gofmt/golangci), Swift Quality (format/dead-code без повторной сборки), Swift Compile и Slop Review с прежней AI semantics. Подготовку инструментов выполнять один раз; отсутствующий инструмент — `infra_error`, без конкурентной Homebrew установки.

### T05 — reporting and timings

Реализовать versioned events/result schema, GitHub summary, bounded/redacted logs, atomic result write и раздельные ordinary/AI timings. Не складывать параллельные durations как wall-clock.

### T06 — one-job workflow

Добавить reusable workflow и SOMA consumer workflow с одним checkout проекта, одним checkout pinned `ci-gates`, одним executor invocation, artifacts, общий check `CI Scope / Checks`, cancellation по ref, PR/merge_group/manual/schedule support и прежним base/head semantics. Предварительный trusted runner admission сохраняется.

### T07 — CI Scope settings/install

Добавить чтение, редактирование, preview и установку manifest/workflow через существующий PR installer. Показать legacy/unified режимы и не превращать локальную script library в скрытую CI policy.

### T08 — CI Scope observation

Показать дочерние проверки, статусы, skip reasons, durations, logs, AI phase, repository/run/attempt/SHA identity и artifacts. Восстанавливать состояние после перезапуска и не превращать отсутствующий report в success.

### T09 — SOMA pilot

До изменения required checks выполнить минимум пять сопоставимых пар старого/нового запуска, отдельно отметить cold/warm cache и AI time, проверить cancellation/rollback/no-orphans и только затем измерить median ordinary phase и принять миграцию.

### T10 — remaining projects

Для каждого проекта создать отдельную задачу и отдельного агента. Каждый недостающий adapter — отдельная задача. Создать manifest, migration PR, compatibility evidence и rollback. Старые и новые workflows не оставлять постоянным дублем.

### T11 — AI optimisation follow-up

В projectmem открыть отдельную задачу на пересмотр локальных моделей, prompts, context size, votes/retries, cache, load/unload и progress reporting. Не оптимизировать это в текущем migration task; не сохранять secrets или полные пользовательские transcripts.

### T12 — independent final audit

Новый агент проверяет весь migration: один required check, полный coverage, policy pinning/admission, cancellation/cleanup, closed-app execution, no hidden skipped, benchmark correctness, rollback и AI projectmem entry. Ошибки проходят тот же repair → new reviewer cycle.

## Приёмка и ограничения

- Не включать VPS Agent/App effects вне разрешённого canary и не менять scheduler authority.
- Не повышать SOMA `.code-linter.json` limits.
- Использовать stdlib/unittest и существующие Xcode test targets; не добавлять framework без необходимости.
- Сначала принять SOMA pilot, затем мигрировать остальные проекты.
- Required checks переключать только после compatibility evidence и rollback.
- Полная приёмка требует green pilot, migration matrix, независимого audit и доказанного восстановления legacy mode.
