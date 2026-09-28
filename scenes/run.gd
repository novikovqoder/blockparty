# Сцена забега (разделы 5, 7, 8, 13 SPEC): строит уровень по seed, спавнит
# своего игрока и удалённых участников, ведёт отсчёт до GO (по часам хоста
# в сети), следит за HUD. Подтверждения событий (монеты, мобы, чекпоинты,
# «Висит», помощь, кооп-объекты, финиш и конец забега) решает хост — сетевую
# часть исполняет Net, в одиночной игре Net играет роль хоста локально, те же
# сигналы EventBus. Здесь же ввод эмоций (клавиши 1–6 и колесо по Q) и
# вытягивание висящего удержанием E (раздел 7).
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

# --- Эмоции и вытягивание (раздел 7) ---

var _emote_wheel: EmoteWheel
var _wheel_hold_left: float = 0.0   # сколько-held Q до открытия колеса
var _last_emote_msec: int = 0       # локальный кулдаун (зеркало проверки хоста)
var _local_bubble: EmoteBubble = null
var _help_markers: Dictionary = {}  # peer_id -> WorldMarker «Помогите!»
var _pull_target: int = 0           # peer_id висящего рядом (0 — никого)
var _pull_hold_left: float = 0.0
var _pull_sent_target: int = 0      # запрос отправлен, ждём подтверждения

@onready var hud: RunHud = $Hud


func _ready() -> void:
	Session.begin_run()
	Interactions.reset()
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
	Net.bind_world(_mobs, checkpoints, LevelBuilder.host_zones(plan))
	Net.report_ready()

	_emote_wheel = EmoteWheel.new()
	add_child(_emote_wheel)

	_countdown_left = B.start_countdown_time
	EventBus.run_countdown_started.emit()


func _physics_process(delta: float) -> void:
	if not _started:
		_process_countdown(delta)
		return
	if not _ended:
		_process_run(delta)
	_update_hang_panel()
	_process_emote_input(delta)
	_process_pull(delta)


func _unhandled_input(event: InputEvent) -> void:
	# Быстрые эмоции 1–6 (раздел 7.5); доступны и в «Висит».
	if not _started or _ended:
		return
	for i: int in 6:
		if event.is_action_pressed("emote_%d" % (i + 1)):
			_send_emote(i + 1)
			get_viewport().set_input_as_handled()
			return


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
	if Session.bot and fmod(Session.run_time, 5.0) < _delta:
		Log.debug("Позиция бота: %s (секция %d)" % [str(player.global_position), Session.current_section])


## Сколько игровых секций берём из пула 14 (раздел 5: 8 секций + старт и финиш).
func _section_count() -> int:
	return B.sections_per_run


func _connect_events() -> void:
	EventBus.checkpoint_reached.connect(_on_checkpoint_reached)
	EventBus.player_respawned.connect(_on_player_respawned)
	EventBus.player_finished.connect(_on_player_finished_local)
	EventBus.run_finished.connect(_on_run_finished)
	EventBus.host_lost.connect(_on_host_lost)
	EventBus.peer_left.connect(_on_peer_left)
	EventBus.emote_shown.connect(_on_emote_shown)
	EventBus.player_pulled.connect(_on_player_pulled)
	EventBus.hang_state_changed.connect(_on_hang_state_changed)
	EventBus.hang_started.connect(_on_local_hang_started)
	EventBus.hang_ended.connect(_on_local_hang_ended)
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


# --- Эмоции (раздел 7.5): клавиши 1–6 и колесо по удержанию Q ---

func _process_emote_input(delta: float) -> void:
	var held: bool = Input.is_action_pressed("emote_wheel")
	if _emote_wheel.is_open():
		if not held:
			var picked: int = _emote_wheel.close()
			if picked > 0:
				_send_emote(picked)
		return
	if held:
		_wheel_hold_left += delta
		if _wheel_hold_left >= B.emote_wheel_delay:
			_emote_wheel.open()
	else:
		_wheel_hold_left = 0.0


func _send_emote(emote_id: int) -> void:
	# Локальный кулдаун — зеркало проверки хоста, чтобы кнопка не «прожималась» зря.
	var now: int = Time.get_ticks_msec()
	if now - _last_emote_msec < int(B.emote_cooldown * 1000.0):
		return
	_last_emote_msec = now
	EventBus.emote_requested.emit(emote_id, player.global_position, player.facing())


# --- Вытягивание висящего удержанием E (раздел 7.1) ---

func _process_pull(delta: float) -> void:
	if not player.control_enabled or player.is_hanging():
		hud.show_pull_hint(false)
		_pull_hold_left = 0.0
		_pull_sent_target = 0
		return
	var target: int = _nearest_hanging_peer()
	if target == 0:
		hud.show_pull_hint(false)
		_pull_hold_left = 0.0
		_pull_sent_target = 0
		return
	hud.show_pull_hint(true)
	if _pull_sent_target == target and Input.is_action_pressed("interact"):
		hud.set_pull_progress(1.0)  # запрос уже ушёл, ждём подтверждение хоста
		return
	if not Input.is_action_pressed("interact"):
		_pull_hold_left = 0.0
		_pull_sent_target = 0
		hud.set_pull_progress(0.0)
		return
	if target != _pull_target:
		_pull_target = target
		_pull_hold_left = 0.0
	_pull_hold_left += delta
	hud.set_pull_progress(_pull_hold_left / B.pull_hold_time)
	if _pull_hold_left >= B.pull_hold_time:
		_pull_sent_target = target
		_pull_hold_left = 0.0
		EventBus.pull_requested.emit(target)


## Ближайший висящий участник в радиусе pull_range (0 — никого).
func _nearest_hanging_peer() -> int:
	var best_peer: int = 0
	var best_dist: float = B.pull_range
	for peer_id: int in Net.players.keys():
		if peer_id == Net.local_peer_id or not bool(Net.players[peer_id]["hanging"]):
			continue
		var remote: RemotePlayer = _remotes.get(peer_id)
		if remote == null:
			continue
		var dist: float = player.global_position.distance_to(remote.global_position)
		if dist <= best_dist:
			best_dist = dist
			best_peer = peer_id
	return best_peer


# --- Пузыри и маркеры-указатели (разделы 7.1, 7.5) ---

## Хост доставил эмоцию: пузырь над автором, «Сюда!» и «Помогите!» — маркеры.
func _on_emote_shown(sender_peer: int, emote_id: int, origin: Vector2, facing: int) -> void:
	if sender_peer == Net.local_peer_id:
		if _local_bubble == null:
			_local_bubble = EmoteBubble.new()
			player.add_child(_local_bubble)
		_local_bubble.position = Vector2(0, -B.hitbox_height * 0.5 - 22.0)
		_local_bubble.show_emote(emote_id)
	else:
		var remote: RemotePlayer = _remotes.get(sender_peer)
		if remote != null:
			remote.show_emote(emote_id)
	if emote_id == 3:
		_spawn_marker(
			WorldMarker.Kind.HERE,
			origin + Vector2(facing * B.here_marker_distance, 0.0),
			B.here_marker_time
		)
	elif emote_id == 6:
		_spawn_marker(WorldMarker.Kind.HELP, origin, B.emote_show_time)


func _spawn_marker(kind: int, at: Vector2, ttl: float) -> void:
	var marker := WorldMarker.new()
	marker.position = at
	add_child(marker)
	marker.setup(kind, ttl)


## Кто-то висит — над ним стрелка «Помогите!» (раздел 7.1): свой — по
## hang_started, чужие — по hang_state_changed от хоста (с дедлайном).
func _on_local_hang_started() -> void:
	_spawn_help_marker(Net.local_peer_id, player.global_position, B.hang_time)


func _on_local_hang_ended() -> void:
	_remove_help_marker(Net.local_peer_id)


func _on_hang_state_changed(peer_id: int, hanging: bool, deadline_run_time: float) -> void:
	if peer_id == Net.local_peer_id:
		return
	var remote: RemotePlayer = _remotes.get(peer_id)
	if remote == null:
		return
	if hanging:
		var ttl: float = maxf(2.0, deadline_run_time - Session.run_time)
		_spawn_help_marker(peer_id, remote.global_position, ttl)
	else:
		_remove_help_marker(peer_id)


func _spawn_help_marker(peer_id: int, at: Vector2, ttl: float) -> void:
	_remove_help_marker(peer_id)
	var marker := WorldMarker.new()
	marker.position = at + Vector2(0, -B.hitbox_height)
	add_child(marker)
	marker.setup(WorldMarker.Kind.HELP, ttl)
	_help_markers[peer_id] = marker


func _remove_help_marker(peer_id: int) -> void:
	if _help_markers.has(peer_id):
		var marker: WorldMarker = _help_markers[peer_id]
		marker.queue_free()
		_help_markers.erase(peer_id)


## Хост подтвердил вытягивание: помощнику — анимация, висящему — подъём на край.
func _on_player_pulled(helper_peer: int, target_peer: int) -> void:
	if helper_peer == Net.local_peer_id:
		player.play_pull()
	if target_peer == Net.local_peer_id:
		player.pulled_up()
	else:
		var remote: RemotePlayer = _remotes.get(target_peer)
		if remote != null:
			remote.rescued()
	_remove_help_marker(target_peer)


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
