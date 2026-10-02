# Blockparty — социальный 3D открытый мир — MVP

Общий кубический остров для Steam, где до 12 незнакомцев гуляют, встречаются,
выполняют небольшие активности вместе и общаются голосом по кнопке.

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

## Зафиксированные версии
| Компонент | Версия |
| --- | --- |
| Godot | 4.7.2.stable.official.ed1daf0bf |
| GodotSteam | GDExtension 4.22.1 (Asset Library) |
| GUT | 9.7.1 |

Версии не меняются без явного решения (раздел 2 SPEC). Актуальные версии также продублированы в docs/STATUS.md.

## Команды
- Первый импорт ассетов (после клонирования): `godot --headless --import`
- Запуск: `godot` (или открыть проект в редакторе Godot той же версии)
- Локальный сетевой тест без Steam: `tools/run_local.sh [N] [--headless]`
  (хост + N клиентов, по умолчанию 3; на Windows — `tools/run_local.ps1`)
- Тесты: `godot --headless -s addons/gut/gut_cmdln.gd`
