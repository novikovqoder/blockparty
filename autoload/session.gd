# Состояние лобби и забега: seed, фаза, часы забега, монеты за забег
# (разделы 5, 8–9 SPEC). Часы забега идут по времени хоста (Net), поэтому
# run_time одинаков у всех участников.
# Не делает: экран лобби и Steam-лобби — этап 4.
extends Node

## Seed уровня забега; --dev-seed попадает сюда, иначе генерируется при старте.
var level_seed: int = -1
## Простой бот для нагрузочных тестов (--bot; водит локального игрока).
var bot: bool = false

## Идёт ли забег сейчас (между GO и концом забега).
var run_active: bool = false
## Время GO по часам хоста, мс (фиксируется один раз при старте).
var go_host_msec: int = 0
## Время от стартового «GO» по часам хоста, с (раздел 6: run_time).
var run_time: float = 0.0
## Монеты, собранные за текущий забег.
var run_coins: int = 0
## Дошёл ли локальный игрок до финиша.
var player_finished: bool = false
## Текущая секция для отладочной панели F3 (пишет сцена забега).
var current_section: int = 0


func _ready() -> void:
	level_seed = Dev.level_seed
	bot = Dev.bot
	if level_seed >= 0:
		Log.info("Фиксированный seed уровня: %d" % level_seed, "Session")
	if bot:
		Log.info("Режим бота включён", "Session")
		if DisplayServer.get_name() == "headless":
			# Нагрузочные прогоны: без ограничения FPS копии игры на сервере
			# без экрана съедают по ядру процессора каждая.
			Engine.max_fps = Dev.HEADLESS_BOT_MAX_FPS
			Log.info("Headless-бот: лимит FPS %d" % Dev.HEADLESS_BOT_MAX_FPS, "Session")


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
	go_host_msec = 0
	run_time = 0.0
	run_coins = 0
	player_finished = false
	current_section = 0
	EventBus.run_coins_changed.emit(0)
	return level_seed


## GO наступил: часы забега пошли от времени хоста (Net.go_host_msec).
func begin_go_clock() -> void:
	go_host_msec = Net.go_host_msec
	run_active = true
	Log.info("Забег начался (seed %d)" % level_seed, "Session")


## Завершить забег (финиш, лимит времени или потеря хоста).
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
