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
const PAL: Palette = preload("res://assets/palette.tres")

## Зоны фототура --shot-dir=PATH (критерий П4.5: 6 скриншотов зон) плюс закат
## на площади — проверка тёплого вечернего света (раздел 7).
const SHOT_ZONES: PackedStringArray = ["plaza", "forest", "ruins", "hills", "crevasse", "lake"]
## Сдвиг часов для снимков: полдень (0.3 суток) для обычных ракурсов — иначе
## тур попадает в рассветные сумерки входа в мир; 0.58 суток (696 с) —
## золотой час заката (тёплый горизонт, низкое солнце, раздел 7).
const SHOT_DAY_FRACTION: float = 0.3
const SHOT_SUNSET_FRACTION: float = 0.58
## Пауза тика проксимити Interactions (раздел 13: «секунда рядом»), с.
const PROXIMITY_TICK: float = 1.0

var _debug: DebugPanel
var _esc_menu: EscMenu
var _hud: WorldHud
var _island: Island
var _player: Player
var _day_cycle: DayCycle
var _ambient: AmbientParticles
## Виньетка (vfx-fix, блок е): полноэкранный ColorRect под HUD —
## затемняет углы, но не интерфейс; видна только в «Высоком качестве».
var _vignette: ColorRect
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
	# Атмосферные частицы (vfx-fix, блок г): светлячки, пыльца, листья.
	_ambient = AmbientParticles.new()
	add_child(_ambient)
	# Виньетка (vfx-fix, блок е) до HUD: рисуется под интерфейсом.
	_vignette = GraphicsQuality.make_vignette()
	add_child(_vignette)
	_spawn_player()
	_apply_graphics_quality()
	_hud = WorldHud.new()
	add_child(_hud)
	var wheel := EmoteWheel.new()
	add_child(wheel)
	wheel.setup(_player)
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
	# Задания жителей (П5.5): узлы на острове и диалог жителя. QuestSystem
	# берёт арт у Island — поэтому после острова; слушатели сети — в _wire_network.
	var quest_system := QuestSystem.new()
	_island.add_child(quest_system)
	add_child(QuestDialog.new())
	# Трекер активных заданий справа сверху (раздел 15); карту (M) точками
	# целей подписывает сама IslandMap.
	add_child(QuestTracker.new())
	if Dev.debug_collisions:
		_draw_debug_collisions(_island)
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
	# Туман по зонам (раздел 16): цвет подмешивается там, где стоит игрок.
	_day_cycle.set_fog_focus(_player.global_position)
	_ambient.set_focus(_player.global_position)
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
			_on_peer_joined_world(
				peer_id, str(Net.players[peer_id]["name"]), Net.peer_character(peer_id)
			)


func _on_peer_joined_world(peer_id: int, player_name: String, character: int) -> void:
	if peer_id == Net.local_peer_id or _remotes.has(peer_id):
		return
	var remote := RemotePlayer.new()
	remote.setup(peer_id, player_name, character)
	add_child(remote)
	_remotes[peer_id] = remote
	Log.info(
		"Игрок «%s» (peer %d, персонаж %d) появился в мире"
		% [player_name, peer_id, character], "World"
	)


func _on_peer_snapshot(peer_id: int, snap: Dictionary, recv_msec: int) -> void:
	var remote: RemotePlayer = _remotes.get(peer_id)
	if remote == null:
		return
	remote.apply_snapshot(snap, recv_msec)


func _on_peer_left(peer_id: int, _player_name: String) -> void:
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
	if Net.mode == "steam":
		# Раздел 11: выход из Steam-мира закрывает и лобби — из меню можно
		# войти в другой мир (dev-режим ENet держит связь для повторного входа).
		Net.leave_steam_world()
	else:
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
	# Персонаж локального игрока — выбранный на экране «Персонаж» (раздел 15;
	# сохранение в user://, дефолт — первый; номер по сети — шаг 8). Цвет тела
	# по хэшу id (раздел 16): в Steam-режиме — Steam id, в ENet и без сети —
	# peer id. Хэш локальный, по сети не передаётся.
	var own_id: int = SteamService.steam_id if SteamService.steam_id != 0 \
		else Net.local_peer_id
	var character := Save.load_character()
	_player.visual.setup(character)
	_player.apply_stats(character)
	_player.visual.setup_palette(own_id)
	Log.info(
		"Персонаж %d, цвет %d (id=%d)" % [character, CharacterModel.palette_index(own_id), own_id],
		"World",
	)
	# Точки интереса бота (раздел 18): зоны появления и Камни духа.
	if Session.bot:
		var targets: Array[Vector3] = []
		for zone_point: Vector3 in _island.spawn_zones.values():
			targets.append(zone_point)
		for node in get_tree().get_nodes_in_group(RespawnStone.GROUP):
			if node is Node3D:
				targets.append((node as Node3D).global_position)
		_player.set_bot_targets(targets)
	# Автопрогон задания жителя (П5.5): клиент проходит «Вечерний чай»,
	# хост стоит у костра — e2e-сверка логов в tools/quest_e2e.sh.
	if Session.quest_bot:
		var quest_bot := QuestBot.new()
		add_child(quest_bot)
		quest_bot.setup(_player)


## Отладка коллизий (--debug-collisions): поверх картинки рисуются
## полупрозрачные оранжевые формы статичных тел острова — видно, где
## предметы с коллизией и совпадает ли она с видимым мешем (чек-лист
## шага 1 П4.5). Рельеф (HeightMapShape3D) не рисуется: его оверлей
## заливал кадр целиком и глушил мелкие формы (vfx-fix). Динамичные
## триггеры (монеты, мобы, вода, расщелина) не рисуются — важны именно
## статичные поверхности.
func _draw_debug_collisions(root: Node) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(1.0, 0.55, 0.15, 0.35)
	var drawn := 0
	for body: Node in root.find_children("*", "StaticBody3D", true, false):
		for child: Node in body.get_children():
			if child is not CollisionShape3D:
				continue
			var shape := child as CollisionShape3D
			if shape.shape == null or shape.shape is HeightMapShape3D:
				continue
			var mesh := MeshInstance3D.new()
			mesh.name = "DebugCollision"
			mesh.mesh = shape.shape.get_debug_mesh()
			mesh.material_override = material
			mesh.transform = shape.transform
			shape.get_parent().add_child(mesh)
			drawn += 1
	Log.info("Отладка коллизий: нарисовано форм — %d" % drawn, "World")


## Качество картинки (разделы 15–16): «Простая графика» — без теней и
## пост-эффектов, туман плотнее (DayCycle), камера видит на 70 м вместо 160
## (слабые встроенные GPU); «Высокое качество» — плюс постобработка
## (блок е: glow, SSAO, виньетка) и объёмный туман с дымкой в Лесу
## и у Озера (шаг 4 П4.5; на compatibility-рендерере серверных скриншотов
## SSAO и объёмный туман недоступны — проверяет владелец).
func _apply_graphics_quality() -> void:
	var tier := GraphicsQuality.tier_from_settings()
	_day_cycle.simple = tier == GraphicsQuality.Tier.SIMPLE
	_ambient.setup(tier)
	_vignette.visible = tier == GraphicsQuality.Tier.HIGH
	GraphicsQuality.apply($WorldEnvironment.environment, $Sun, tier)
	if tier == GraphicsQuality.Tier.SIMPLE:
		_player.camera.set_view_distance(B.view_distance_simple)
	if tier == GraphicsQuality.Tier.HIGH:
		for zone: String in ["forest", "lake"]:
			var center := _island.spawn_point(zone)
			var color := IslandGen.zone_blend(
				Vector2(center.x, center.z), PAL.zone_fog
			)
			add_child(GraphicsQuality.make_zone_fog(center, color))


## Фототур (шаг 2 П4.5, «Самопроверка картинки»): временная камера снимает
## спавн с высоты глаз, вид под ноги, персонажа крупно спереди и сбоку,
## все 6 зон общим планом и закат — PNG в Dev.shot_dir (создаётся),
## после чего закрывает игру. Только для проверок (tools/screenshots.sh).
func _screenshot_tour() -> void:
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	DirAccess.make_dir_recursive_absolute(Dev.shot_dir)
	# Диагностика «молочного кадра» (шаг 2 П4.5): переменные окружения
	# отключают части картинки по одной — виновник ищется без правки кода.
	# SHOT_NOWATER=1 скрыть воду, SHOT_NOFOG=1 выключить туман,
	# SHOT_ONLY=eye — только ракурсы у игрока (быстрый прогон).
	if OS.get_environment("SHOT_NOWATER") == "1":
		for water: WaterArea in _island.find_children("*", "WaterArea"):
			water.visible = false
	_set_day_fraction(SHOT_DAY_FRACTION)
	if OS.get_environment("SHOT_NOFOG") == "1":
		($WorldEnvironment.environment as Environment).fog_enabled = false
	# SHOT_LAB=1 — лаборатория света в контексте мира: DayCycle выключен,
	# параметры берутся из SHOT_SUN / SHOT_AMB (поиск причины белого рельефа).
	if OS.get_environment("SHOT_LAB") == "1":
		_day_cycle.set_process(false)
		var env := $WorldEnvironment.environment as Environment
		$Sun.light_energy = OS.get_environment("SHOT_SUN").to_float()
		$Sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
		env.ambient_light_energy = OS.get_environment("SHOT_AMB").to_float()
		if not OS.get_environment("SHOT_DENSITY").is_empty():
			env.fog_density = OS.get_environment("SHOT_DENSITY").to_float()
		if OS.get_environment("SHOT_AERIAL") == "0":
			env.fog_aerial_perspective = 0.0
	await _shot_player_views(camera)
	if OS.get_environment("SHOT_ONLY") == "eye":
		get_tree().quit()
		return
	for zone: String in SHOT_ZONES:
		await _shot_zone(camera, zone, false)
	await _shot_zone(camera, "plaza", true)
	get_tree().quit()


## Часы мира на нужную долю суток (0 — рассвет): снимки делаются днём,
## иначе тур попадает в сумерки сразу после входа в мир. Сдвигаем offset,
## не эпоху: часы процесса насчитывают секунды, вычитание суток из эпохи
## дало бы отрицательное значение — гвард «мир не создан» занулял время.
func _set_day_fraction(fraction: float) -> void:
	var elapsed := maxf(0.0, float(Net.host_time_now_msec() - Net.world_epoch_msec) / 1000.0)
	Net.world_time_offset_sec = fraction * B.day_cycle_sec - elapsed


## Ракурсы персонажа: высота глаз 1.5 м, взгляд вперёд (модель игрока
## в покое смотрит в +Z), «под ноги» — та же точка с наклоном вниз,
## «крупно» — камера в 2.8 м перед лицом и сбоку.
func _shot_player_views(camera: Camera3D) -> void:
	await get_tree().create_timer(0.2).timeout
	var feet: Vector3 = _player.global_position
	var eye: Vector3 = feet + Vector3.UP * 1.5
	var forward := Vector3.BACK  # +Z: куда смотрит модель в покое.
	camera.global_position = eye + forward * 0.4  # не из-за головы модели
	camera.look_at(eye + forward * 10.0 + Vector3.DOWN * 1.5)
	await _snap(camera, "eye_plaza.png")
	camera.global_position = eye
	# SHOT_PITCH — диагностика «земли нет под ногами»: наклон кадра вниз,
	# градусы (по умолчанию 62 — взгляд на точку в 0.8 м перед ногами).
	var feet_pitch: float = OS.get_environment("SHOT_PITCH").to_float()
	if feet_pitch <= 0.0:
		feet_pitch = rad_to_deg(atan(1.5 / 0.8))
	camera.look_at(feet + forward * (1.5 / tan(deg_to_rad(feet_pitch))))
	await _snap(camera, "feet_plaza.png")
	camera.global_position = feet + forward * 2.8 + Vector3.UP * 1.1
	camera.look_at(feet + Vector3.UP * 0.9)
	await _snap(camera, "char_front.png")
	camera.global_position = feet + Vector3(2.8, 1.1, 0.0)
	camera.look_at(feet + Vector3.UP * 0.9)
	await _snap(camera, "char_side.png")
	# SHOT_NPC=1 — Тимьян на пне у костра крупно (визуальная проверка капсулы
	# коллизии жителя, vfx-fix: камера видит и костёр за ним).
	# SHOT_NPCHULL=1 — то же место, но визуал жителя скрыт: в кадре остаётся
	# только полупрозрачная капсула (измерение габарита без модели).
	if OS.get_environment("SHOT_NPC") == "1":
		for node in get_tree().get_nodes_in_group(Townsfolk.TOWNSFOLK_GROUP):
			var folk := node as Townsfolk
			if folk == null or not folk.sitting:
				continue
			if OS.get_environment("SHOT_NPCHULL") == "1":
				for child: Node in folk.get_children():
					if child.name != "Body":
						(child as Node3D).visible = false
			var stump: Vector3 = folk.global_position
			camera.global_position = stump + Vector3(2.5, 1.2, 2.6)
			camera.look_at(stump + Vector3.UP * 0.8)
			await _snap(camera, "npc_thyme.png")
			break


## Пауза на кадр рендера и сохранение снимка.
func _snap(camera: Camera3D, file_name: String) -> void:
	await get_tree().create_timer(0.3).timeout
	Log.info("Тур: %s primitives=%d draw_calls=%d"
		% [
			file_name,
			get_viewport().get_render_info(
				Viewport.RENDER_INFO_TYPE_VISIBLE,
				Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME,
			),
			get_viewport().get_render_info(
				Viewport.RENDER_INFO_TYPE_VISIBLE,
				Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME,
			),
		], "World")
	var image := get_viewport().get_texture().get_image()
	var path: String = Dev.shot_dir.path_join(file_name)
	image.save_png(path)
	Log.info("Скриншот сохранён: " + path, "World")


func _shot_zone(camera: Camera3D, zone: String, sunset: bool) -> void:
	# Закат: ставим часы мира на конец дня (0.6 суток, раздел 7).
	if sunset:
		_set_day_fraction(SHOT_SUNSET_FRACTION)
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
	await _snap(camera, "sunset.png" if sunset else "zone_%s.png" % zone)
