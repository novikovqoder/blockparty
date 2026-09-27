# Сцена забега (разделы 5, 8, 13 SPEC): строит уровень по seed, спавнит своего
# игрока и удалённых участников, ведёт отсчёт до GO (по часам хоста в сети),
# следит за HUD. Подтверждения событий (монеты, мобы, чекпоинты, «Висит»,
# финиш и конец забега) решает хост — сетевую часть исполняет Net, в одиночной
# игре Net играет роль хоста локально, те же сигналы EventBus.
# Не делает: паузу и выход из забега по Esc (этап 7).
class_name RunScene
extends Node2D

const B: Balance = preload("res://gameplay/balance.tres")
const PLAYER_SCENE: PackedScene = preload("res://gameplay/player/player.tscn")
const MAIN_MENU_SCENE: String = "res://scenes/main_menu.tscn"

var plan: LevelPlan
var player: Player

var _mobs: Dictionary = {}  # spawn_id -> Mob (проверки хоста, Net.bind_world)
var _remotes: Dictionary = {}  # peer_id -> RemotePlayer
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
	var order: Array[String] = []
	for entry: Dictionary in plan.entries:
		order.append(entry["id"])
	Log.info(
		"Уровень собран: seed=%d, секций=%d [%s], мобов=%d, монет=%d, ширина=%d px"
		% [Session.level_seed, plan.entries.size(), " → ".join(order), plan.mob_spawns.size(), plan.coin_spawns.size(), plan.total_width],
		"Run"
	)

	player = PLAYER_SCENE.instantiate()
	player.position = plan.spawn_point
	add_child(player)
	player.set_camera_limits(plan.total_width)
	Net.set_local_player(player)
	_checkpoint = plan.spawn_point
	_spawn_remotes()

	hud.setup(plan.entries.size())
	hud.set_play_again_allowed(not Net.is_networked() or Net.is_host())
	_connect_events()

	for child: Node in get_node("Level").get_children():
		var mob := child as Mob
		if mob != null:
			_mobs[mob.spawn_id] = mob
	var checkpoints: Array[Vector2] = [plan.spawn_point]
	for cp: Dictionary in plan.checkpoints:
		checkpoints.append(Vector2(cp["x"], cp["y"]))
	Net.bind_world(_mobs, checkpoints)
	Net.report_ready()

	_countdown_left = B.start_countdown_time
	EventBus.run_countdown_started.emit()


func _physics_process(delta: float) -> void:
	if not _started:
		_process_countdown(delta)
		return
	if not _ended:
		_process_run(delta)
	_update_hang_panel()


## Отсчёт до GO: в сети — по часам хоста (rpc_go на 3 с позже времени хоста),
## в одиночной игре — локальный таймер.
func _process_countdown(delta: float) -> void:
	if Net.is_networked():
		if not Net.go_scheduled():
			hud.show_countdown_waiting()
			return
		var left := Net.seconds_until_go()
		hud.show_countdown(maxf(left, 0.0))
		if left <= 0.0:
			_go()
	else:
		_countdown_left -= delta
		hud.show_countdown(_countdown_left)
		if _countdown_left <= 0.0:
			Net.mark_go_now()
			_go()


func _go() -> void:
	_started = true
	Session.begin_go_clock()
	EventBus.run_go.emit()


func _process_run(_delta: float) -> void:
	# Часы run_time и условия конца забега ведёт Net (по времени хоста).
	hud.set_time_left(B.run_time_limit - Session.run_time, B.timer_visible_last)
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
	EventBus.player_respawned.connect(_on_player_respawned)
	EventBus.player_finished.connect(_on_player_finished_local)
	EventBus.run_finished.connect(_on_run_finished)
	EventBus.host_lost.connect(_on_host_lost)
	EventBus.peer_left.connect(_on_peer_left)
	hud.give_up_pressed.connect(func() -> void: player.give_up_hang())
	hud.play_again_pressed.connect(_on_play_again)
	hud.to_menu_pressed.connect(func() -> void: get_tree().change_scene_to_file(MAIN_MENU_SCENE))


## Чужие игроки из ростера (без себя); позиции до первых снапшотов — старт.
func _spawn_remotes() -> void:
	if not Net.is_networked():
		return
	for peer_id: int in Net.players.keys():
		if peer_id == Net.local_peer_id:
			continue
		var remote := RemotePlayer.new()
		remote.setup(peer_id, str(Net.players[peer_id]["name"]))
		remote.position = plan.spawn_point
		add_child(remote)
		Net.register_remote(peer_id, remote)
		_remotes[peer_id] = remote
	Log.info("Удалённых игроков на сцене: %d" % _remotes.size(), "Run")


func _update_section_hud() -> void:
	var x := player.global_position.x
	for i: int in plan.entries.size():
		var entry: Dictionary = plan.entries[i]
		if x < entry["offset_x"] + entry["width"] or i == plan.entries.size() - 1:
			hud.set_section(i + 1, plan.entries.size())
			Session.current_section = i + 1
			return


func _update_hang_panel() -> void:
	if player.is_hanging():
		hud.set_hang_time(player.hang_time_left())


# --- Чекпоинты и «Висит» (разделы 5, 7.1); подтверждение — хост через Net ---

## Чекпоинты идут только вперёд: возврат назад не откатывает точку.
func _on_checkpoint_reached(index: int, position: Vector2) -> void:
	if index <= _checkpoint_index:
		return
	_checkpoint_index = index
	_checkpoint = position
	Log.debug("Чекпоинт секции %d (%d, %d)" % [index, int(position.x), int(position.y)], "Run")


## Хост подтвердил возврат на чекпоинт (rpc_respawn) — телепорт своего игрока.
func _on_player_respawned(position: Vector2) -> void:
	player.respawn_at(position)


# --- Финиш и конец забега (решает хост; сюда приходит только результат) ---

## Свой финиш: в сети показываем «ждём остальных», финальный оверлей придёт
## от хоста (rpc_run_ended); в одиночной игре всё завершится сразу.
func _on_player_finished_local(_run_time: float) -> void:
	if Net.is_networked():
		hud.show_wait_finish(Session.run_coins)


func _on_run_finished(finished: bool, time: float) -> void:
	if _ended:
		return
	_ended = true
	hud.show_end(finished, Session.run_coins)
	Log.info(
		"Забег завершён: finished=%s, время=%.1f с, монет=%d"
		% [str(finished), time, Session.run_coins],
		"Run"
	)


func _on_host_lost(_reason: String) -> void:
	# Раздел 8: хост отключился — экран с сообщением, дальше только в меню.
	_ended = true
	hud.show_host_lost()


## Участник вышел из забега: персонаж исчезает (раздел 8).
func _on_peer_left(peer_id: int) -> void:
	if _remotes.has(peer_id):
		var remote: RemotePlayer = _remotes[peer_id]
		remote.queue_free()
		_remotes.erase(peer_id)
		Log.info("Персонаж игрока %d удалён (вышел из забега)" % peer_id, "Run")


func _on_play_again() -> void:
	if Net.is_networked():
		# Новый забег той же компанией запускает хост (раздел 9 — этап 6).
		if Net.is_host():
			Net.start_run_as_host()
		return
	# Одиночный «Ещё раз»: новый seed (фиксированный --dev-seed сохранит уровень).
	Session.level_seed = Dev.level_seed
	get_tree().change_scene_to_file("res://scenes/run.tscn")
