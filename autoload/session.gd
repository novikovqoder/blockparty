# Состояние лобби и забега: участники, seed, фаза забега, чекпоинты (разделы 8–9 SPEC).
# Не делает на этапе 0: реальное состояние появится на этапах 2–3.
extends Node

## Seed уровня забега; --dev-seed попадает сюда, хост-забег перезапишет (этап 2).
var level_seed: int = -1
## Простой бот для нагрузочных тестов (--bot, реализация — этап 2).
var bot: bool = false


func _ready() -> void:
	level_seed = Dev.level_seed
	bot = Dev.bot
	if level_seed >= 0:
		Log.info("Фиксированный seed уровня: %d" % level_seed, "Session")
	if bot:
		Log.info("Режим бота включён (реализация — этап 2)", "Session")
