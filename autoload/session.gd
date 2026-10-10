# Состояние мира и сессии игрока (разделы 7, 10, 13 SPEC): вход и выход
# (мир открыт постоянно, финиша нет), часы мира world_time по часам хоста
# (Net), время сессии и монеты за пребывание. Замена состоянию забега v1.
# Не делает: сохранение между сессиями (Save — П8), историю встреч (П7).
extends Node

## Простой бот для нагрузочных тестов (--bot; ходьба по острову — этап П3).
var bot: bool = false
## Автопрогон задания жителя (--quest-bot, П5.5): телепорты вместо ходьбы,
## прогулочный бот при этом не включается.
var quest_bot: bool = false
## Зона появления из --dev-spawn (пустая строка — стандартная Площадь).
var spawn_zone: String = ""

## Локальный игрок в мире (сцена мира загружена и применена).
var in_world: bool = false
## Часы мира, с (раздел 7: цикл дня 20 минут; у всех одинаково — от хоста).
var world_time: float = 0.0
## Время текущего пребывания в мире, с (экран «Встречи», лог плейтеста).
var session_time: float = 0.0
## Монеты, собранные за текущее пребывание в мире.
var world_coins: int = 0


func _ready() -> void:
	bot = Dev.bot
	quest_bot = Dev.quest_bot
	spawn_zone = Dev.spawn_zone
	if bot:
		Log.info("Режим бота включён", "Session")
	if quest_bot:
		Log.info("Режим автопрогона заданий включён", "Session")
	if bot or quest_bot:
		if DisplayServer.get_name() == "headless":
			# Нагрузочные прогоны: без ограничения FPS копии игры на сервере
			# без экрана съедают по ядру процессора каждая.
			Engine.max_fps = Dev.HEADLESS_BOT_MAX_FPS
			Log.info("Headless-бот: лимит FPS %d" % Dev.HEADLESS_BOT_MAX_FPS, "Session")
	if spawn_zone != "":
		Log.info("Зона появления из --dev-spawn: %s" % spawn_zone, "Session")


func _process(delta: float) -> void:
	if not in_world:
		return
	world_time = Net.world_time_sec()
	session_time += delta


## Войти в мир: часы подхватываются, счётчики сессии сбрасываются.
func enter_world() -> void:
	if in_world:
		return
	# Локальный мир без сети: часы мира стартуют сейчас (раздел 7).
	Net.begin_world_clock()
	in_world = true
	world_time = Net.world_time_sec()
	session_time = 0.0
	world_coins = 0
	EventBus.world_entered.emit()
	Log.info("Вход в мир (world_time=%.1f с)" % world_time, "Session")


## Выйти из мира (меню Esc, «Выйти из мира», потеря хоста).
func leave_world() -> void:
	if not in_world:
		return
	in_world = false
	Log.info(
		"Выход из мира: %.1f с, монет=%d" % [session_time, world_coins],
		"Session",
	)
	EventBus.world_left.emit(session_time)


## Начислить монеты (мобы, монеты острова, кооп-награды) и оповестить HUD.
func add_world_coins(amount: int) -> void:
	world_coins += amount
	EventBus.world_coins_changed.emit(world_coins)
