# Социальный кооп-платформер — MVP

Кооперативный 2D-платформер для Steam, где 2–12 незнакомцев проходят уровень вместе,
говорят голосом по кнопке и помогают друг другу.

- Полное ТЗ: [docs/SPEC.md](docs/SPEC.md)
- Текущий этап: [docs/STATUS.md](docs/STATUS.md)
- Правила для Claude Code: [CLAUDE.md](CLAUDE.md)
- Чек-лист плейтеста: [docs/playtest_checklist.md](docs/playtest_checklist.md)

## Подготовка сервера
```bash
bash setup_server.sh ~/mvp_kit.zip ~/game-mvp
```
Скрипт ставит Godot (headless), GUT и GodotSteam, распаковывает комплект,
записывает версии в docs/STATUS.md и делает первый коммит. Запускать можно повторно.

## Проверка на своём ПК
- Godot той же версии, что в docs/STATUS.md
- Steam-клиент с выполненным входом (для этапов 4–5)
- `git lfs install` перед клонированием

## Команды
- Локальный сетевой тест без Steam: `tools/run_local.sh` (появится на этапе 0)
- Тесты: `godot --headless -s addons/gut/gut_cmdln.gd`
