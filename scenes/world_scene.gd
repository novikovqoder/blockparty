# Сцена мира (раздел 6 SPEC): остров из gameplay/world/island.tscn
# (сгенерирован tools/generate_island.gd, коммитится — по сети не передаётся),
# игроки, мобы и монеты (в острове), цикл дня (DayCycle), карта (M), HUD.
# Спавн — на Площади или в зоне --dev-spawn. «Простая графика» (раздел 15):
# без теней, ближе туман и дальность камеры — флаг --simple-graphics
# (экран настроек — П8). По сети (раздел 10): снапшоты локального игрока
# шлёт Net, чужие игроки — RemotePlayer по снапшотам хоста, вход в идущий
# мир — world_state. Проксимити-очки Interactions (раздел 13) — тик раз
# в секунду по позициям ремоутов.
extends Node3D

const MENU_SCENE: String = "res://scenes/main_menu.tscn"
const PLAYER_SCENE: PackedScene = preload("res://gameplay/player/player.tscn")
const ISLAND_SCENE: PackedScene = preload("res://gameplay/world/island.tscn")
const B: Balance = preload("res://gameplay/balance.tres")

## Зоны фототура --shot-dir=PATH (критерий П2: 6 скриншотов зон) плюс ночь
## на площади — проверка «мягкой светлой ночи» (раздел 7).
const SHOT_ZONES: PackedStringArray = ["plaza", "forest", "ruins", "hills", "crevasse", "lake"]
## Сдвиг часов для ночного снимка: 0.7 суток — глубокая ночь (день 0.6).
const NIGHT_TIME_SEC: float = 840.0
## Пауза тика проксимити Interactions (раздел 13: «секунда рядом»), с.
const PROXIMITY_TICK: float = 1.0

var _debug: DebugPanel
var _esc_menu: EscMenu
var _hud: WorldHud
var _island: Island
var _player: Player
var _day_cycle: DayCycle
var _leaving: bool = false
var _zone_now: String = ""
var _remotes: Dictionary = {}  # peer_id -> RemotePlayer
var _proximity_accum: float = 0.0


func _ready() -> void:
	_island = ISLAND_SCENE.instantiate() as Island
	add_child(_island)
	_day_cycle = DayCycle.new()
	add_child(_day_cycle)
	_day_cycle.setup($Sun, $WorldEnvironment)
	_spawn_player()
	_apply_simple_graphics()
	_hud = WorldHud.new()
	add_child(_hud)
	var map := IslandMap.new()
	add_child(map)
	map.track(_island, _player)
	_esc_menu = EscMenu.new()
	add_child(_esc_menu)
	_esc_menu.exit_requested.connect(_exit_to_menu)
	_debug = DebugPanel.new()
	add_child(_debug)
	_debug.watch_player(_player)
	_debug.watch_island(_island)
	_wire_network()
	Session.enter_world()
	Net.entered_world()
	EventBus.host_lost.connect(_on_host_lost)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not Dev.shot_dir.is_empty():
		_screenshot_tour()


func _process(delta: float) -> void:
	# Название зоны при переходе (подсказка HUD, раздел 6).
	var zone := _island.zone_name_at(_player.global_position)
	if zone != _zone_now:
		_zone_now = zone
		_hud.show_zone(zone)
	_proximity_tick(delta)


## Подключение к сети (раздел 10): события чужих игроков, применение
## world_state (пакет мог прийти, пока игрок был в меню) и объявление себя.
func _wire_network() -> void:
	EventBus.peer_joined_world.connect(_on_peer_joined_world)
	EventBus.peer_snapshot.connect(_on_peer_snapshot)
	EventBus.peer_left.connect(_on_peer_left)
	Net.replay_world_state()
	# Кто уже в мире (поздний вход): появляем их персонажей.
	for peer_id: int in Net.players.keys():
		if peer_id != Net.local_peer_id and Net._peer_in_world(peer_id):
			_on_peer_joined_world(peer_id, str(Net.players[peer_id]["name"]))


func _on_peer_joined_world(peer_id: int, player_name: String) -> void:
	if peer_id == Net.local_peer_id or _remotes.has(peer_id):
		return
	var remote := RemotePlayer.new()
	remote.setup(peer_id, player_name)
	add_child(remote)
	_remotes[peer_id] = remote
	Log.info("Игрок «%s» (peer %d) появился в мире" % [player_name, peer_id], "World")


func _on_peer_snapshot(peer_id: int, snap: Dictionary, recv_msec: int) -> void:
	var remote: RemotePlayer = _remotes.get(peer_id)
	if remote == null:
		return
	remote.apply_snapshot(snap, recv_msec)


func _on_peer_left(peer_id: int) -> void:
	var remote: RemotePlayer = _remotes.get(peer_id)
	if remote == null:
		return
	remote.queue_free()
	_remotes.erase(peer_id)
	Log.info("Персонаж игрока %d исчез" % peer_id, "World")


## Секунда рядом (раздел 13): очки по всем ремоутам в радиусе proximity_m.
func _proximity_tick(delta: float) -> void:
	_proximity_accum += delta
	if _proximity_accum < PROXIMITY_TICK:
		return
	_proximity_accum = 0.0
	for peer_id: int in _remotes:
		var remote: RemotePlayer = _remotes[peer_id]
		if remote.last_position().distance_to(_player.global_position) <= B.proximity_m:
			Interactions.add_points(
				peer_id, Interactions.KIND_PROXIMITY, B.pts_proximity, Session.world_time
			)


func _unhandled_input(event: InputEvent) -> void:
	# Esc — меню (освобождает курсор, раздел 5); мир не на паузе (раздел 15).
	if event.is_action_pressed("pause"):
		_esc_menu.toggle()


func _exit_to_menu() -> void:
	if _leaving:
		return
	_leaving = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Net.left_world()
	Session.leave_world()
	get_tree().call_deferred("change_scene_to_file", MENU_SCENE)


func _on_host_lost(_reason: String) -> void:
	# Хост вышел: мир закрылся у всех; экран «Встречи» на его месте — П7.
	_exit_to_menu()


func _spawn_player() -> void:
	_player = PLAYER_SCENE.instantiate() as Player
	_player.position = _island.spawn_point(Session.spawn_zone)
	add_child(_player)
	# Точки интереса бота (раздел 18): зоны появления и Камни духа.
	if Session.bot:
		var targets: Array[Vector3] = []
		for zone_point: Vector3 in _island.spawn_zones.values():
			targets.append(zone_point)
		for node in get_tree().get_nodes_in_group(RespawnStone.GROUP):
			if node is Node3D:
				targets.append((node as Node3D).global_position)
		_player.set_bot_targets(targets)


## «Простая графика» (раздел 15): без теней, туман плотнее (DayCycle), камера
## видит на 70 м вместо 160 — слабые встроенные GPU не тянут весь остров.
func _apply_simple_graphics() -> void:
	_day_cycle.simple = Settings.simple_graphics
	if Settings.simple_graphics:
		$Sun.shadow_enabled = false
		_player.camera.set_view_distance(B.view_distance_simple)


## Фототур: временная камера обходит зоны острова и сохраняет PNG в
## Dev.shot_dir (создаётся), после чего закрывает игру. Только для проверок.
func _screenshot_tour() -> void:
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	DirAccess.make_dir_recursive_absolute(Dev.shot_dir)
	for zone: String in SHOT_ZONES:
		await _shot_zone(camera, zone, false)
	await _shot_zone(camera, "plaza", true)
	get_tree().quit()


func _shot_zone(camera: Camera3D, zone: String, night: bool) -> void:
	# Ночь: сдвигаем эпоху мира назад — world_time = теперь + NIGHT_TIME_SEC.
	if night:
		Net.world_epoch_msec -= int(NIGHT_TIME_SEC * 1000.0)
		await get_tree().create_timer(0.3).timeout
	var target := _island.spawn_point(zone)
	var cam_pos := target + Vector3(14.0, 12.0, 18.0)
	# Смещение от точки зоны может попасть в склон (у площади земля на 15 м —
	# камера оказывалась внутри рельефа, снимок выходил «изнутри» земли).
	# Прощупываем поверхность лучом сверху и поднимаем камеру над ней.
	# Луч — из idle-кадра (после таймера): в physics-шаге space state
	# заблокирован и intersect_ray молча возвращает пустой словарь.
	await get_tree().create_timer(0.2).timeout
	var query := PhysicsRayQueryParameters3D.create(
		cam_pos + Vector3.UP * 60.0, cam_pos,
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		cam_pos.y = maxf(cam_pos.y, (hit.position as Vector3).y + 2.0)
	camera.global_position = cam_pos
	camera.look_at(target + Vector3(0.0, 1.0, 0.0))
	await get_tree().create_timer(0.3).timeout
	var image := get_viewport().get_texture().get_image()
	var name := ("p2_night.png" if night else "p2_%s.png" % zone)
	var path: String = Dev.shot_dir.path_join(name)
	image.save_png(path)
	Log.info("Скриншот сохранён: " + path, "World")
