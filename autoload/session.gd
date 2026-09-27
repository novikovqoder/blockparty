# Состояние лобби и забега: seed, фаза, часы забега, монеты за забег
# (разделы 5, 8–9 SPEC). На этапе 1 забег одиночный: роль «хоста» играет
# сцена run.tscn локально.
# Не делает: участники и сетевые роли — этап 2, лобби — этап 4.
extends Node

## Seed уровня забега; --dev-seed попадает сюда, иначе генерируется при старте.
var level_seed: int = -1
## Простой бот для нагрузочных тестов (--bot, реализация — этап 2).
var bot: bool = false

## Идёт ли забег сейчас (между run_go и финишем/лимитом времени).
var run_active: bool = false
## Время от стартового «GO» по часам забега, с (раздел 6: run_time).
var run_time: float = 0.0
## Монеты, собранные за текущий забег.
var run_coins: int = 0
## Дошёл ли локальный игрок до финиша.
var player_finished: bool = false


func _ready() -> void:
	level_seed = Dev.level_seed
	bot = Dev.bot
	if level_seed >= 0:
		Log.info("Фиксированный seed уровня: %d" % level_seed, "Session")
	if bot:
		Log.info("Режим бота включён (реализация — этап 2)", "Session")


## Начать забег: фиксирует seed (генерирует случайный, если не задан --dev-seed)
## и сбрасывает счётчики. Случайный seed выбирается один раз и только здесь —
## сама генерация уровня детерминирована (раздел 5 SPEC).
func begin_run() -> int:
	if level_seed < 0:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		level_seed = rng.randi() & 0x7FFFFFFF
		Log.info("Сгенерирован seed уровня: %d" % level_seed, "Session")
	run_active = false
	run_time = 0.0
	run_coins = 0
	player_finished = false
	EventBus.run_coins_changed.emit(0)
	return level_seed


## Разрешить движение после отсчёта (вызывает сцена забега).
func start_run_clock() -> void:
	run_active = true
	Log.info("Забег начался (seed %d)" % level_seed, "Session")


## Завершить забег (финиш или лимит времени).
func end_run(finished: bool) -> void:
	run_active = false
	player_finished = finished
	Log.info(
		"Забег завершён: finished=%s, time=%.1f с, монет=%d"
		% [str(finished), run_time, run_coins],
		"Session",
	)


## Начислить монеты за забег (подбор, мобы, награды) и оповестить HUD.
func add_run_coins(amount: int) -> void:
	run_coins += amount
	EventBus.run_coins_changed.emit(run_coins)
