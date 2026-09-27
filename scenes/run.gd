# Сцена забега (разделы 5, 8, 13 SPEC): фиксирует seed, строит уровень по плану,
# спавнит игрока, ведёт отсчёт 3-2-1-GO и часы run_time, следит за лимитом
# 10 минут и финишем. На этапе 1 забег одиночный: локальная роль «хоста» —
# подтверждение подбора монет и смерти мобов (раздел 6) выполняет эта сцена;
# на этапе 2 логика переедет в сетевой слой без смены сигналов EventBus.
# Не делает: паузу и выход из забега по Esc (этап 7), ботов (этап 2).
class_name RunScene
extends Node2D

const B: Balance = preload("res://gameplay/balance.tres")
const PLAYER_SCENE: PackedScene = preload("res://gameplay/player/player.tscn")
const MAIN_MENU_SCENE: String = "res://scenes/main_menu.tscn"

var plan: LevelPlan
var player: Player

var _mobs: Dictionary = {}  # spawn_id -> Mob (для проверок «хоста»)
var _picked_coins: Dictionary = {}  # spawn_id -> true (первый запрос выигрывает)
var _checkpoint: Vector2 = Vector2.ZERO
var _checkpoint_index: int = 0
var _countdown_left: float = 0.0
var _started: bool = false
var _ended: bool = false

@onready var hud: RunHud = $Hud


func _ready() -> void:
	Session.begin_run()
	plan = LevelPlanner.plan(Session.level_seed, LevelBuilder.pool(), _section_count())
	add_child(LevelBuilder.build(plan))
	Log.info(
		"Уровень собран: seed=%d, секций=%d, мобов=%d, монет=%d, ширина=%d px"
		% [Session.level_seed, plan.entries.size(), plan.mob_spawns.size(), plan.coin_spawns.size(), plan.total_width],
		"Run"
	)

	player = PLAYER_SCENE.instantiate()
	player.position = plan.spawn_point
	add_child(player)
	player.set_camera_limits(plan.total_width)
	_checkpoint = plan.spawn_point

	hud.setup(plan.entries.size())
	_connect_events()

	_countdown_left = B.start_countdown_time
	EventBus.run_countdown_started.emit()


func _physics_process(delta: float) -> void:
	if not _started:
		_process_countdown(delta)
		return
	if not _ended:
		_process_run(delta)
	_update_hang_panel()


func _process_countdown(delta: float) -> void:
	_countdown_left -= delta
	hud.show_countdown(_countdown_left)
	if _countdown_left <= 0.0:
		_started = true
		Session.start_run_clock()
		EventBus.run_go.emit()


func _process_run(delta: float) -> void:
	Session.run_time += delta
	hud.set_time_left(B.run_time_limit - Session.run_time, B.timer_visible_last)
	if Session.run_time >= B.run_time_limit:
		_end_run(false)
		return
	_update_section_hud()


## Сколько игровых секций брать из пула (этап 1: по одной каждого типа,
# раздел 15; в будущем — 8 из 14, раздел 5).
func _section_count() -> int:
	var count := 0
	for def: ChunkDef in LevelBuilder.pool():
		if def.type != ChunkDef.Type.START and def.type != ChunkDef.Type.FINISH:
			count += 1
	return count


func _connect_events() -> void:
	EventBus.checkpoint_reached.connect(_on_checkpoint_reached)
	EventBus.hang_ended.connect(_on_hang_ended)
	EventBus.coin_pickup_requested.connect(_on_coin_pickup_requested)
	EventBus.mob_hit_requested.connect(_on_mob_hit_requested)
	EventBus.player_finished.connect(_on_player_finished)
	hud.give_up_pressed.connect(func() -> void: player.give_up_hang())
	hud.play_again_pressed.connect(_on_play_again)
	hud.to_menu_pressed.connect(func() -> void: get_tree().change_scene_to_file(MAIN_MENU_SCENE))

	for child: Node in get_node("Level").get_children():
		var mob := child as Mob
		if mob != null:
			_mobs[mob.spawn_id] = mob


func _update_section_hud() -> void:
	var x := player.global_position.x
	for i: int in plan.entries.size():
		var entry: Dictionary = plan.entries[i]
		if x < entry["offset_x"] + entry["width"] or i == plan.entries.size() - 1:
			hud.set_section(i + 1, plan.entries.size())
			return


func _update_hang_panel() -> void:
	if player.is_hanging():
		hud.set_hang_time(player.hang_time_left())


# --- Локальная роль «хоста» (раздел 6; на этапе 2 переедет в сеть) ---

## Первый запрос на монету выигрывает; подтверждение рассылается всем.
func _on_coin_pickup_requested(spawn_id: int) -> void:
	if _picked_coins.has(spawn_id):
		return
	_picked_coins[spawn_id] = true
	EventBus.coin_picked.emit(spawn_id)
	Session.add_run_coins(B.coin_value)


## Проверка попадания по мобу: моб жив и атакующий в пределах 96 px
## от расчётной позиции моба (раздел 6, шаг 3).
func _on_mob_hit_requested(spawn_id: int, _run_time: float, from_position: Vector2) -> void:
	var mob: Mob = _mobs.get(spawn_id)
	if mob == null or not mob.alive:
		return
	if mob.global_position.distance_to(from_position) > B.hit_accept_range:
		return  # отказ: эффект удара уже сыгран локально, это допустимо
	EventBus.mob_killed.emit(spawn_id, 0)
	Session.add_run_coins(B.mob_kill_coins)


# --- Чекпоинты и «Висит» (разделы 5, 7.1) ---

## Чекпоинты идут только вперёд: возврат назад не откатывает точку.
func _on_checkpoint_reached(index: int, position: Vector2) -> void:
	if index <= _checkpoint_index:
		return
	_checkpoint_index = index
	_checkpoint = position
	Log.debug("Чекпоинт секции %d (%d, %d)" % [index, int(position.x), int(position.y)], "Run")


func _on_hang_ended() -> void:
	# Возврат на последний чекпоинт (таймаут 8 с или «Сдаться», раздел 7.1).
	player.respawn_at(_checkpoint)


# --- Финиш и конец забега (разделы 7.6, 5) ---

func _on_player_finished(run_time: float) -> void:
	if _ended:
		return
	Session.add_run_coins(B.finish_coins)
	_end_run(true, run_time)


func _end_run(finished: bool, time: float = -1.0) -> void:
	if _ended:
		return
	_ended = true
	if time < 0.0:
		time = Session.run_time
	Session.end_run(finished)
	EventBus.run_finished.emit(finished, time)
	hud.show_end(finished, Session.run_coins)
	Log.info(
		"Забег завершён: finished=%s, время=%.1f с, монет=%d"
		% [str(finished), time, Session.run_coins],
		"Run"
	)


func _on_play_again() -> void:
	# Новый забег с новым seed (фиксированный --dev-seed сохранит уровень).
	Session.level_seed = Dev.level_seed
	get_tree().change_scene_to_file("res://scenes/run.tscn")
