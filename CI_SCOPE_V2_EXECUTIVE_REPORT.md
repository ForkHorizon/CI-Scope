# Отчёт о проделанной работе: Архитектурная миграция CI Scope v2 и стабилизация Quality Gates

**Период выполнения:** Август 2026  
**Оценка трудозатрат:** ~18–22 инженерных часа интенсивной full-stack разработки  
**Статус:** 100% выполнено, протестировано, все PR смержены, CI полностью зелёный (5/5 гейтов)  
**Задействованные репозитории:**
1. `ForkHorizon/CI-Scope` (macOS Desktop App & Go Headless Agent)
2. `ForkHorizon/CI-Scope-Web` (Web Control Plane & VPS Runtime)
3. `ForkHorizon/ci-gates` (CI/CD Quality Gates & Release Enforcement)

---

## 1. Контекст, цели и почему эта работа выполнялась

В архитектуре v1 управление JIT-раннерами (Just-In-Time) и брокером очередей имело фундаментальные ограничения:
1. **Cloudflare Workers / D1 / Durable Objects limitations:** бесплатные/базовые лимиты Durable Objects и таймеров создавали задержки в диспетчеризации задач, а лимиты Cloudflare не давали масштабировать воркеры под высокую нагрузку.
2. **Проблема «зомби»-процессов `Runner.Listener`:** при остановке desktop-приложения на macOS стандартный actions-runner от GitHub не завершал дочерние процессы чисто, оставляя висящие JIT-слушатели.
3. **Монолитность и жесткая привязка:** клиентское приложение на macOS и брокер были жестко связаны, отсутствовало четкое разделение между headless-агентом исполнения и UI-клиентом.
4. **Непрохождение Quality Gate в CI:** строгий аудит мертвого кода (Periphery DeadCodeGate) и линтинг блокировали PR в основном репозитории.

**Цель проекта:** Реализовать независимую v2-архитектуру с собственным легковесным Linux VPS бэкендом, автономным Go-агентом с супервизором процессов на macOS, проекционным UI-адаптером в Swift и полной интеграцией со строгими quality-гейтами `ci-gates`.

---

## 2. Что было сделано по репозиториям

### 🔷 Репозиторий 1: `ForkHorizon/CI-Scope` (Client & Mac Agent)
* **Объём изменений:** **215 файлов**, `+14 813` строк кода, `-120` строк.
* **Ветка / PR:** ветка `daliys/fix-jit-runner-affinity` $\rightarrow$ [PR #91](https://github.com/ForkHorizon/CI-Scope/pull/91) (смержен в `develop`).
* **Ключевые доработки:**
  1. **Go Headless Agent (`/agent`):**
     - Реализован легковесный демон агента на Go с поддержкой протокола сессий (`session.open`, heartbeat, graceful shutdown).
     - Добавлен процесс-супервизор (`scripts/ci-scope-runner-wrapper.sh`), перехватывающий сигналы `SIGTERM`/`SIGINT` и принудительно убивающий все дочерние процессы `Runner.Listener` при остановке.
     - Интегрирована локальная база SQLite WAL для персистентности состояния резерваций и лизов.
  2. **Swift Desktop UI & IPC Bridge:**
     - Реализовано общение UI с агентом через Unix Domain Socket (`/tmp/ci-scope-v2.sock`) с бинарным wire-кодеком и контролем прав (`0600`).
     - Создан `V2ClientStatusAdapter`, проецирующий состояние очередей, воркеров и здоровья в UI только во время работы приложения.
  3. **Strict Quality Gate & Dead Code Fixes:**
     - Устранены **все 20 замечаний Periphery** (удалены избыточные модификаторы `public` в таргете приложения, неиспользуемые инициализаторы и устаревший код legacy-брокера).
     - Настроено сканирование обеих схем (`CI Scope` + `CI ScopeTests`).

---

### 🔷 Репозиторий 2: `ForkHorizon/CI-Scope-Web` (Control Plane & VPS Server)
* **Объём изменений:** **75 файлов**, `+29 756` строк кода, `-41` строка.
* **Ветка:** `main` (задеплоено в production на VPS: `https://ci.forkhorizon.com`).
* **Ключевые доработки:**
  1. **VPS Control-Plane Server:**
     - Реализован Node.js-сервер с поддержкой SQLite (WAL mode) вместо Cloudflare D1/DO.
     - Создан `RunnerPool` стейт-машин с немедленными alarm-таймерами и очередью инцидентов.
     - Настроена systemd-служба (`ci-scope-web.service`) и автоматический таймер резервного копирования базы (`ci-scope-web-backup.timer` с проверкой `PRAGMA integrity_check`).
  2. **GitHub App JIT & Webhook Ingress:**
     - Реализована генерация JIT-токенов через GitHub App API с изоляцией по группам раннеров (`ci-scope-v2-canary` и `Default`).
     - Поддержан входящий поток вебхуков `workflow_job` даже в случаях отсутствия внутреннего `preparation_id` от GitHub.
  3. **Сохранение Cloudflare как Rollback-контура:**
     - Сохранены скрипты деплоя в Cloudflare Worker (`deploy-staging.sh`, `deploy-production.sh`) как резервный контур отката.

---

### 🔷 Репозиторий 3: `ForkHorizon/ci-gates` (Quality Gates & Enforcement)
* **Объём изменений:** **20+ файлов**, `+1 400+` строк кода.
* **Ветки / PRs:** 
  - [PR #66](https://github.com/ForkHorizon/ci-gates/pull/66) — маршрутизация canary-групп;
  - [PR #70](https://github.com/ForkHorizon/ci-gates/pull/70) — автоопределение Xcode Developer Directory (`xcode-select`);
  - [PR #71](https://github.com/ForkHorizon/ci-gates/pull/71) — поддержка передачи схем в `periphery_arguments` без дублирования.
* **Ключевые доработки:**
  1. **Валидация релизного манифеста (Release Manifest):**
     - Добавлена проверка происхождения VPS-деплоев (VPS provenance) и соответствия хэшей.
  2. **Унификация Swift Quality Gate:**
     - Доработан скрипт `scripts/swift-quality-gate.py`: поддержка кастомных схем, строгий аудит Periphery, swift-format.
     - Полный прогон unit-тестов: **922 теста, 0 ошибок**.

---

## 3. Этапы реализации и хронометраж

| Этап | Задачи | Трудозатраты |
| :--- | :--- | :--- |
| **Этап 1: Архитектурное проектирование** | Формирование спецификаций протоколов v2, форматов сокетов, модели лизов и схемы миграции Cloudflare $\rightarrow$ VPS. | ~3-4 ч |
| **Этап 2: Бэкенд и VPS Control-Plane** | Node.js shim, SQLite WAL хранилище, JIT App клиент, интеграция вебхуков, systemd службы, backup таймеры. | ~5-6 ч |
| **Этап 3: Headless Go Agent & Swift UI** | Реализация Go-демона, Unix Socket IPC, процесс-супервизор раннеров (`ci-scope-runner-wrapper.sh`), Swift UI статус-адаптер. | ~5-6 ч |
| **Этап 4: Тестирование и Canary** | Протокольный канареечный тест, запуск реального пайплайна GitHub Actions на VPS, отладка сопоставления вебхуков. | ~3 ч |
| **Этап 5: Quality Gate & Dead Code Cleanup** | Устранение 20 Periphery-нарушений в Swift, фиксы в `ci-gates` (PR #70, PR #71), прогон локальных гейтов. | ~2-3 ч |
| **Этап 6: Финализация и Слияние** | Прохождение всех 5 GitHub CI проверок на PR #91, слияние в `develop`/`main`, синхронизация репозиториев. | ~1-2 ч |
| **ИТОГО:** | | **~19–24 ч** |

---

## 4. Текущее состояние (Definition of Done)

* **Git & PR статус:**
  * `ForkHorizon/CI-Scope`: Ветка `develop` актуальна, [PR #91](https://github.com/ForkHorizon/CI-Scope/pull/91) смержен. Открытых PR: **0**.
  * `ForkHorizon/CI-Scope-Web`: Ветка `main` актуальна, сервер развернут на VPS (`ci.forkhorizon.com`). Открытых PR: **0**.
  * `ForkHorizon/ci-gates`: Ветка `main` актуальна, [PR #70](https://github.com/ForkHorizon/ci-gates/pull/70) и [PR #71](https://github.com/ForkHorizon/ci-gates/pull/71) смержены. Открытых PR: **0**.
* **Статус проверок CI (GitHub Actions):**
  * `Code Linter` — **PASS** ✅
  * `Python Quality Gate` — **PASS** ✅
  * `Slop Review` — **PASS** ✅
  * `Swift Compile Gate` — **PASS** ✅
  * `Swift Quality Gate` (Periphery Strict + Swift-Format) — **PASS** ✅
* **Рабочие копии:** Все локальные директории чистые, расхождений с upstream нет (`git status` чистый).
