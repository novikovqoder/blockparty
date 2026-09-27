# STATUS

## Текущий этап
Этап 0 завершён, ожидается подтверждение. Следующий — этап 1 «Одиночный геймплей» (docs/SPEC.md, раздел 15).

## Зафиксированные версии
- Godot: 4.7.2.stable.official.ed1daf0bf
- GodotSteam: GodotSteam GDExtension 4.22.1 (Asset Library)
- GUT: v9.7.1

## Отчёты по этапам
<!-- Claude Code добавляет блок в конце каждого этапа по шаблону ниже -->

### Этап 0 — Каркас проекта (2026-09-27)

**Сделано:**
- `project.godot`: автолоады в порядке зависимостей, окно 1280×720,
  stretch `canvas_items`/`keep_height`, рендерер `gl_compatibility`,
  переводы ru/en (fallback `en`), иконка.
- Структура папок из раздела 3 SPEC (`net/`, `gameplay/…`, `scenes/`, `ui/`,
  `assets/`, `i18n/`, `tests/`, `tools/`).
- Автолоады: `log.gd` — полностью рабочий (консоль + `user://logs/game_*.log`,
  хранятся последние 10); `steam_service.gd` — инициализация Steam, при успехе
  пишет в лог SteamID и persona name; `dev.gd` — разбор всех аргументов из
  раздела 3 (`--dev-host`, `--dev-join`, `--dev-name`, `--dev-seed`, `--bot`,
  `--net-lag`, `--net-loss`, `--log-net`); остальные (`event_bus`, `settings`,
  `save`, `net`, `session`, `voice`, `interactions`) — заглушки с комментариями
  «что делает / чего не делает»; `net.gd` и `session.gd` уже логируют выбранный
  dev-режим и seed.
- Сцены: `boot.tscn` (ждёт Steam; без Steam — окно «Steam не запущен» с кнопками
  «Играть офлайн (режим разработки)» и «Выход»), заглушки `main_menu`, `lobby`,
  `run`, `results`. Локализация через метаданные `tr_key` (`ui/loc_labels.gd`).
- GodotSteam подключён (уже был в `addons/`); имена API сверены с фактически
  установленной библиотекой вызовами в headless: `steamInitEx(480, true) ->
  Dictionary{status, verbal}`, `status == 0` — успех, `getSteamID()`,
  `getPersonaName()`. Примечание: сайт godotsteam.com с этого сервера недоступен,
  использована локальная документация аддона + фактические сигнатуры ClassDB.
- GUT настроен (`.gutconfig.json`), тест `tests/test_dev_args.gd` — 6 тестов,
  21 проверка, все зелёные.
- `tools/run_local.sh` (хост + N клиентов, `--headless` для сервера, cleanup по
  Ctrl+C) и `tools/run_local.ps1` для Windows.
- `assets/CREDITS.md` заведён (пока только `icon.svg`).
- Версии записаны в README.

**Как проверить на сервере (headless):**
- `godot --headless --quit` — запуск без ошибок, в логе офлайн-ветка Steam.
- `godot --headless --quit -- --dev-host --dev-seed=42 --net-lag=150` — в логе
  разобранные аргументы (Net, Session).
- `godot --headless -s addons/gut/gut_cmdln.gd` — все тесты зелёные.
- `tools/run_local.sh 3 --headless` — 4 процесса, затем Ctrl+C убирает все.

**Как проверить вручную (ПК с Windows):**
- Открыть проект в Godot 4.7.2, запустить: без запущенного Steam — окно
  «Steam не запущен», кнопка «Играть офлайн» ведёт в меню-заглушку.
- С запущенным Steam: в логе `user://logs/game_*.log` — SteamID и persona name,
  загрузка сразу в меню.
- `tools/run_local.ps1` — 4 окна игры (пока просто заглушки меню, реальная
  сеть — этап 2).
- Переключить язык системы на en — интерфейс на английском.

**Отложено:**
- Реальная сеть ENet (этап 2), боты (этап 2), Steam-лобби (этап 4).
- Настройки/сохранения: чтение-запись `config.cfg`/`save.json` (этап 7).
- `ui/theme.tres`, шрифт с кириллицей (этапы 1+; сейчас системный шрифт Godot).

**Известные проблемы:**
- После клонирования репозитория нужен `godot --headless --import` — без него
  переводы не сгенерируются (`.translation` в `.gitignore`).
- Без установленного GodotSteam автолоад `SteamService` не скомпилируется;
  в MVP аддон всегда в репозитории, поэтому допустимо.

<!-- Шаблон:
### Этап N — название (дата)
**Сделано:**
**Как проверить вручную:**
**Отложено:**
**Известные проблемы:**
-->
