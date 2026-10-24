# Сцена мира (раздел 6 SPEC): остров из gameplay/world/island.tscn
# (сгенерирован tools/generate_island.gd, коммитится — по сети не передаётся),
# игроки, мобы (в острове), цикл дня (DayCycle), HUD.
# Спавн — на Площади или в зоне --dev-spawn. «Простая графика» (раздел 15):
# без теней, ближе туман и дальность камеры — флаг --simple-graphics
# (экран настроек — П8). По сети (раздел 10): снапшоты локального игрока
# шлёт Net, чужие игроки — RemotePlayer по снапшотам хоста, вход в идущий
# мир — world_state.
extends Node3D

## П10 (экран загрузки): мир построен и игрок в нём — LoadingScreenBU уходит
## только после этого сигнала, ни одного серого кадра. У клиента — после
## применения world_state (чужие игроки на месте), у хоста и офлайн — после
## осадки спавна игрока.
signal world_ready

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
## Частота кадров GIF-серий (финал П5.8): 12/с — движения читаются, серия
## 6 с — 72 кадра (сборка GIF — tools/make_gif.py).
const SHOT_SERIES_FPS: int = 12

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


func _ready() -> void:
	_island = ISLAND_SCENE.instantiate() as Island
	add_child(_island)
	_day_cycle = DayCycle.new()
	add_child(_day_cycle)
	_day_cycle.setup($WorldEnvironment/SunLight, $WorldEnvironment)
	# Атмосферные частицы (vfx-fix, блок г): светлячки, пыльца, листья.
	_ambient = AmbientParticles.new()
	add_child(_ambient)
	# Виньетка (vfx-fix, блок е) до HUD: рисуется под интерфейсом.
	_vignette = GraphicsQuality.make_vignette()
	add_child(_vignette)
	_spawn_player()
	# Частицы из-под ног (переделка П9): покрытие по запечённым данным острова.
	_player.setup_foot_fx(_island.art())
	_apply_graphics_quality()
	_hud = WorldHud.new()
	add_child(_hud)
	_esc_menu = EscMenu.new()
	add_child(_esc_menu)
	_esc_menu.exit_requested.connect(_exit_to_menu)
	_debug = DebugPanel.new()
	add_child(_debug)
	_debug.watch_player(_player)
	_debug.watch_island(_island)
	if Dev.debug_collisions:
		_draw_debug_collisions(_island)
	_wire_network()
	Session.enter_world()
	Net.entered_world()
	EventBus.host_lost.connect(_on_host_lost)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_announce_world_ready()
	if not Dev.shot_dir.is_empty():
		_screenshot_tour()


## П10 (экран загрузки): объявить мир готовым. Клиент в идущем мире ждёт
## world_state хоста (replay уже в _wire_network), хост и офлайн — осадку
## спавна игрока. Лимит 15 c < ready_timeout экрана (30 c): не отпускаем
## экран навсегда, если хост молчит.
func _announce_world_ready() -> void:
	if Net.is_networked() and not Net.is_host():
		# SPEC П10 4.6: клиент ждёт снимка мира хоста — экран загрузки
		# показывает «Подключение к миру» вместо стадий по готовности.
		if LoadingScreenBU.current != null:
			LoadingScreenBU.current.set_status(&"BU_LOAD_CONNECT")
		var waited := 0
		while Net.last_world_state.is_empty():
			await get_tree().physics_frame
			waited += 1
			if waited > 900:
				Log.warn("world_state не пришёл за 15 c — мир без чужих игроков",
					"World")
				break
	for i: int in 5:
		await get_tree().physics_frame
	world_ready.emit()


func _process(delta: float) -> void:
	# Название зоны при переходе (подсказка HUD, раздел 6).
	var zone := _island.zone_name_at(_player.global_position)
	if zone != _zone_now:
		_zone_now = zone
		_hud.show_zone(zone)
	# Туман по зонам (раздел 16): цвет подмешивается там, где стоит игрок.
	_day_cycle.set_fog_focus(_player.global_position)
	_ambient.set_focus(_player.global_position)
	# Адаптивная тесселяция рельефа вокруг игрока (доработка-2 П5.13, П1):
	# чанки в радиусе 50 м — квад 0.5 м, с бюджетом на перестройку за кадр.
	_island.update_viewer(_player.global_position)


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
	# Частицы из-под ног чужого игрока — по тем же покрытиям острова (П9).
	remote.setup_foot_fx(_island.art())
	_remotes[peer_id] = remote
	Log.info(
		"Игрок «%s» (peer %d) появился в мире" % [player_name, peer_id],
		"World",
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
	get_tree().call_deferred("change_scene_to_file", Dev.MENU_SCENE)


func _on_host_lost(_reason: String) -> void:
	# Хост вышел: мир закрылся у всех, возврат в меню (экран «Встречи»
	# вычищен с наследием Blockparty, born-unblessed).
	_exit_to_menu()


func _spawn_player() -> void:
	_player = PLAYER_SCENE.instantiate() as Player
	_player.position = _island.spawn_point(Session.spawn_zone)
	add_child(_player)
	# Модель игрока одна на всех (редактор внешности вычищен с наследием
	# Blockparty, born-unblessed) — настраивать по игроку нечего.
	# Точки интереса бота (раздел 18): зоны появления и Камни духа.
	if Session.bot:
		var targets: Array[Vector3] = []
		for zone_point: Vector3 in _island.spawn_zones.values():
			targets.append(zone_point)
		for node in get_tree().get_nodes_in_group(RespawnStone.GROUP):
			if node is Node3D:
				targets.append((node as Node3D).global_position)
		_player.set_bot_targets(targets)
	# Самопроверка анимаций (--selftest-anim, возврат П5.8): позы и
	# скиннинг модели локального игрока в запущенном мире — печатает
	# SELFTEST-ANIM: PASS/FAIL и выходит (код 1 при FAIL); гоняется и на
	# экспортированных сборках, чтобы ловить проблемы экспорта.
	if Session.selftest_anim:
		_selftest_anim(_player.visual)
	# Самопроверка мира (--selftest-world, доработка П5.13): тангенты чанков,
	# текстурная земля и коллизия во всех зонах, предметы не висят и не под
	# водой, вода в чаше озера — печатает SELFTEST-WORLD: PASS/FAIL и выходит
	# (код 1 при FAIL); гоняется и на экспортированных сборках.
	if Session.selftest_world:
		_selftest_world()


## Прогон WorldSelfCheck на острове и выход (--selftest-world): статичные
## данные запечённого мира, кадров ждать не нужно. Печатает
## SELFTEST-WORLD: PASS/FAIL и выходит (код 1 при FAIL).
func _selftest_world() -> void:
	for i: int in 10:
		await get_tree().physics_frame
	var result: Dictionary = WorldSelfCheck.run(_island, true)
	if result["ok"]:
		print("SELFTEST-WORLD: PASS")
		get_tree().quit(0)
		return
	print("SELFTEST-WORLD: FAIL")
	for reason: String in result["reasons"]:
		print("SELFTEST-WORLD: %s" % reason)
	get_tree().quit(1)


## Прогон самопроверки анимаций на модели локального игрока и выход
## (--selftest-anim): герой Born Unblessed — AnimSelfCheckBU (позы костей
## покой/ходьба, резолв дорожек библиотеки sword, скиннинг ног) плюс
## физический лендинг-сценарий Д2 (RealismCheck: бег, прыжок, 2 с после
## касания — статичный присед не едет по земле). Всё блокирующее,
## KNOWN-FAIL нет. Прежние проверки блочной UBC-модели (пол × наряд,
## скольжение стоп на клипах, диапазоны рук, посадка MCO-одежды)
## вычищены вместе с ней (born-unblessed). Печатает SELFTEST-ANIM:
## PASS/FAIL и выходит (код 1 при FAIL); гоняется и на экспортированных
## сборках, чтобы ловить проблемы экспорта.
func _selftest_anim(visual: CharacterVisual) -> void:
	for i: int in 40:
		await get_tree().physics_frame
	var result: Dictionary = await AnimSelfCheckBU.run(visual, true)
	var reasons: PackedStringArray = PackedStringArray()
	if not result["ok"]:
		for reason: String in result["reasons"]:
			reasons.append(reason)
	# Приземление с зажатым движением (Д2): физический сценарий на
	# локальном игроке — бег, прыжок, 2 с после касания; блокирующий.
	print("SELFTEST-ANIM: приземление на бегу (сценарий Д2)")
	var landing: Dictionary = await RealismCheck.check_landing_blend(
		_player, "run", true)
	if not landing["ok"]:
		for reason: String in landing["reasons"]:
			reasons.append(reason)
	if reasons.is_empty():
		print("SELFTEST-ANIM: PASS")
		get_tree().quit(0)
		return
	print("SELFTEST-ANIM: FAIL")
	for reason: String in reasons:
		print("SELFTEST-ANIM: %s" % reason)
	get_tree().quit(1)


## Отладка коллизий (--debug-collisions): поверх картинки рисуются
## полупрозрачные оранжевые формы статичных тел острова — видно, где
## предметы с коллизией и совпадает ли она с видимым мешем (чек-лист
## шага 1 П4.5). Рельеф (HeightMapShape3D) не рисуется: его оверлей
## заливал кадр целиком и глушил мелкие формы (vfx-fix). Динамичные
## триггеры (мобы, вода, расщелина) не рисуются — важны именно
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
	# Viewport — для смещения мипов текстур: «Простая графика» сэмплит
	# 2K-текстуры Леса из мипа 1K (П5.7 блок 7).
	GraphicsQuality.apply(
		$WorldEnvironment.environment, $WorldEnvironment/SunLight, tier,
		get_viewport(), $WorldEnvironment/MoonLight)
	# Трава и мелкие предметы: «Простая графика» прячет lowpoly-траву
	# и приближает дальность предметов. Метод существовал с П4.5, но
	# не вызывался (найдено в П5.7 блоке 7).
	(_island.get_node("IslandView") as IslandView).set_simple_graphics(
		tier == GraphicsQuality.Tier.SIMPLE)
	if tier == GraphicsQuality.Tier.SIMPLE:
		_player.camera.set_view_distance(B.view_distance_simple)
		# Доработка-2 П5.13, П3: вода Boujie растворяется ближе к камере
		# (fade 46–66 м) — при far 70 не остаётся видимого обрыва воды.
		for node: Node in get_tree().get_nodes_in_group("water_surface"):
			(node as WaterArea).set_fade_distance(46.0, 66.0)
	if tier == GraphicsQuality.Tier.HIGH:
		# Лес (П5.7 блок 3): сгусток шире зоны деревьев (~56 м) — объёмный
		# туман стелется по всей реалистичной части; у Озера прежний компакт.
		var center := _island.spawn_point("forest")
		var color := IslandGen.zone_blend(
			Vector2(center.x, center.z), PAL.zone_fog
		)
		add_child(GraphicsQuality.make_zone_fog(center, color, 64.0))
		center = _island.spawn_point("lake")
		color = IslandGen.zone_blend(Vector2(center.x, center.z), PAL.zone_fog)
		add_child(GraphicsQuality.make_zone_fog(center, color))


## Фототур (шаг 2 П4.5, «Самопроверка картинки»): временная камера снимает
## спавн с высоты глаз, вид под ноги, персонажа крупно спереди и сбоку,
## все 6 зон общим планом и закат — PNG в Dev.shot_dir (создаётся),
## после чего закрывает игру. Только для проверок (tools/screenshots.sh).
func _screenshot_tour() -> void:
	# П10 (экран загрузки): мир мог открыться через LoadingScreenBU — ждём его
	# ухода, иначе первый кадр тура снимет экран загрузки, а не мир. Экран сам
	# уходит не позже ready_timeout (30 с) — страховка 40 с.
	var load_waited := 0
	while LoadingScreenBU.current != null and load_waited < 2400:
		await get_tree().process_frame
		load_waited += 1
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
	# SHOT_SIMPLE=1 — «Простая графика» для серверного стенда: после П5.7
	# лес тянет ~3 млн треугольников, и llvmpipe рендерит кадр с тенями
	# минутами; без теней тур укладывается в разумное время.
	if OS.get_environment("SHOT_SIMPLE") == "1":
		Settings.simple_graphics = true
		_apply_graphics_quality()
	# SHOT_FPS=секунды — замер FPS (П5.9 блок 9): прожить в мире N секунд
	# (после SHOT_FPS_WAIT ожидания входа ботов), собрать кадровые интервалы
	# и напечатать статистику FPS-PROBE. Зона — --dev-spawn, режим графики —
	# флаги --simple-graphics / --high-quality; игрок и камера обычные.
	if not OS.get_environment("SHOT_FPS").is_empty():
		await _fps_probe(
			maxf(5.0, OS.get_environment("SHOT_FPS").to_float()))
		get_tree().quit()
		return
	# SHOT_P57=1 — тур П5.7: только Лес с фиксированных точек (день и закат,
	# снимки «было — стало» реалистичной переделки), без общих облётов.
	# SHOT_FRACTION=0..1 — снять в другой точке суток (например, ночь).
	var shot_fraction := SHOT_DAY_FRACTION
	if not OS.get_environment("SHOT_FRACTION").is_empty():
		shot_fraction = clampf(
			OS.get_environment("SHOT_FRACTION").to_float(), 0.0, 1.0)
	# SHOT_SPOT="x,z,yaw[,pitch]" — одиночный кадр из произвольной точки мира
	# (день): прицельная самопроверка деталей — ирисы у валуна, мох на
	# камне. pitch, град (минус — вниз): верх глыбы иначе в кадр не попасть.
	if not OS.get_environment("SHOT_SPOT").is_empty():
		var parts := OS.get_environment("SHOT_SPOT").split(",")
		_freeze_day_fraction(shot_fraction)
		var spot := Vector2(parts[0].to_float(), parts[1].to_float())
		var ground := _ground_at(spot)
		var eye := Vector3(spot.x, ground + 1.5, spot.y)
		var yaw := deg_to_rad(parts[2].to_float())
		var pitch := deg_to_rad(parts[3].to_float()) if parts.size() > 3 else 0.0
		var fwd := Vector3(
			-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
		camera.global_position = eye
		camera.look_at(eye + fwd, Vector3.UP)
		await _snap(camera, "spot_check.png")
		get_tree().quit()
		return
	if OS.get_environment("SHOT_P57") == "1":
		_set_day_fraction(shot_fraction)
		await _shot_p57_forest(camera)
		get_tree().quit()
		return
	# Серия кадров для GIF (сборка — tools/make_gif.py): SHOT_FLY=1 —
	# пролёт камеры над Лесом. Длина — SHOT_SECONDS, темп — SHOT_SERIES_FPS.
	# Съёмки клипов блочного персонажа (SHOT_CLIP/SHOT_ACTOR) вычищены
	# вместе с UBC-моделью (born-unblessed).
	if OS.get_environment("SHOT_FLY") == "1":
		_player.visible = false
		await _shot_p58_series(camera)
		get_tree().quit()
		return
	_freeze_day_fraction(shot_fraction)
	if OS.get_environment("SHOT_NOFOG") == "1":
		($WorldEnvironment.environment as Environment).fog_enabled = false
	# SHOT_LAB=1 — лаборатория света в контексте мира: DayCycle выключен,
	# параметры берутся из SHOT_SUN / SHOT_AMB (поиск причины белого рельефа).
	if OS.get_environment("SHOT_LAB") == "1":
		_day_cycle.set_process(false)
		var env := $WorldEnvironment.environment as Environment
		$WorldEnvironment/SunLight.light_energy = OS.get_environment("SHOT_SUN").to_float()
		$WorldEnvironment/SunLight.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
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


## Поставить и ЗАМОРОЗИТЬ долю суток на время снимка: DayCycle ведёт купол
## по Session.world_time, а те текут от реальных часов — кадр на llvmpipe
## рендерится минутами, и к моменту захвата фаза уезжала на четверть суток
## («день» снимался ночью, П5.9 блок 8). Останавливаем цикл, ставим фазу и
## применяем её к куполу напрямую: ждать кадр, пока цикл применит сам,
## нельзя — на медленном рендере ожидание уводило фазу ещё на ~100 с.
func _freeze_day_fraction(fraction: float) -> void:
	_day_cycle.set_process(false)
	_set_day_fraction(fraction)
	# Session.world_time — выборка часов раз в тик: после сдвига offset она
	# ещё держит старое время, и купол применялся бы не той фазы. Точим
	# вручную и подаём тот же фокус тумана, что и _process мира (игрок).
	Session.world_time = Net.world_time_sec()
	_day_cycle.set_fog_focus(_player.global_position)
	_day_cycle.apply_now()
	Log.info("FREEZE-DBG fraction=%.3f world_time=%.1f"
		% [fraction, Session.world_time], "World")


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



## Тур П5.7: зона Лес с фиксированных точек на уровне глаз персонажа (1.5 м
## над рельефом), день и закат. Точки зашиты в коде — снимки «до» и «после»
## переделки делаются с одних и тех же ракурсов (кадры сравнимы). Высота
## земли берётся рейкастом, поэтому тур переживёт замену рельефа Леса.
const P57_FOREST_POINTS: Array[Vector2] = [
	Vector2(-52.0, -52.0),  # центр зоны, взгляд к Площади
	Vector2(-33.0, -41.0),  # опушка к Площади, взгляд вглубь леса
	Vector2(-70.0, -62.0),  # глубина леса, взгляд на восток
	Vector2(-47.0, -71.0),  # южная часть, взгляд на юг
	Vector2(-61.0, -36.0),  # северная опушка, взгляд на юго-восток
]
const P57_FOREST_YAWS: Array[float] = [223.0, 45.0, 270.0, 180.0, 210.0]


func _shot_p57_forest(camera: Camera3D) -> void:
	# Долю суток замораживаем перед КАЖДЫМ кадром: сутки длятся day_cycle_sec
	# реального времени, кадр на llvmpipe рендерится минуты — при одной
	# установке на серию время уезжало на полсуток и «день» снимался ночью
	# (П5.9, блок 8).
	for i: int in P57_FOREST_POINTS.size():
		_freeze_day_fraction(SHOT_DAY_FRACTION)
		var ground := _ground_at(P57_FOREST_POINTS[i])
		var eye := Vector3(P57_FOREST_POINTS[i].x, ground + 1.5, P57_FOREST_POINTS[i].y)
		var yaw := deg_to_rad(P57_FOREST_YAWS[i])
		var look := eye + Vector3(-sin(yaw), 0.0, -cos(yaw))
		camera.global_position = eye
		camera.look_at(look, Vector3.UP)
		await _snap(camera, "p57_forest_day_%d.png" % (i + 1))
	for i: int in P57_FOREST_POINTS.size():
		_freeze_day_fraction(SHOT_SUNSET_FRACTION)
		var ground := _ground_at(P57_FOREST_POINTS[i])
		var eye := Vector3(P57_FOREST_POINTS[i].x, ground + 1.5, P57_FOREST_POINTS[i].y)
		var yaw := deg_to_rad(P57_FOREST_YAWS[i])
		var look := eye + Vector3(-sin(yaw), 0.0, -cos(yaw))
		camera.global_position = eye
		camera.look_at(look, Vector3.UP)
		await _snap(camera, "p57_forest_sunset_%d.png" % (i + 1))


## Серия кадров пролёта над Лесом (GIF — tools/make_gif.py, SHOT_FLY=1):
## время мира остановлено (Engine.time_scale = 0: часы, ландшафт стоят;
## шейдерный огонь и вода на TIME — живут), траектория — чистая функция
## кадра: рваный темп рендера llvmpipe не ломает равномерность фаз.
func _shot_p58_series(camera: Camera3D) -> void:
	var seconds := 8.0
	if not OS.get_environment("SHOT_SECONDS").is_empty():
		seconds = clampf(
			OS.get_environment("SHOT_SECONDS").to_float(), 2.0, 12.0)
	var frames := int(roundf(seconds * SHOT_SERIES_FPS))
	_set_day_fraction(SHOT_DAY_FRACTION)
	await get_tree().create_timer(0.6).timeout
	await _record_series(camera, "fly_forest", frames,
		func(i: int, _t: float) -> void:
			_fly_forest_frame(camera, float(i) / float(frames)))


## Записать серию: кадры frame_%04d.rgb (сырые RGBA8, размер окна) в
## подкаталоге Dev.shot_dir/<sub>/ — GIF-энкодер (tools/make_gif.py, чистый
## Python без PIL) читает их напрямую, без PNG-декодера. На каждом кадре
## вызывается on_frame(i, t), t — время клипа (шаг 1/SHOT_SERIES_FPS);
## сохраняется нарисованный кадр после frame_post_draw.
func _record_series(
		camera: Camera3D, sub: String, frames: int, on_frame: Callable) -> void:
	Engine.time_scale = 0.0
	var dir: String = Dev.shot_dir.path_join(sub)
	DirAccess.make_dir_recursive_absolute(dir)
	Log.info("Серия %s: %d кадров @ %d fps" % [sub, frames, SHOT_SERIES_FPS],
		"World")
	var started := Time.get_ticks_msec()
	for i: int in frames:
		on_frame.call(i, float(i) / SHOT_SERIES_FPS)
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		var frame_path := dir.path_join("frame_%04d.rgb" % i)
		var file := FileAccess.open(frame_path, FileAccess.WRITE)
		if file != null:
			file.store_buffer(img.get_data())
			file.close()
		if i % 12 == 11:
			Log.info("Серия %s: %d/%d кадров (%.1f с)"
				% [sub, i + 1, frames, (Time.get_ticks_msec() - started) / 1000.0],
				"World")
	Engine.time_scale = 1.0


## Пролёт над Лесом: квадратичная дуга Безье от опушки к Площади через
## глубину леса, высота 9 → 5 м; камера смотрит по ходу с наклоном вниз.
func _fly_forest_frame(camera: Camera3D, u: float) -> void:
	var p0 := Vector3(-30.0, _ground_at(Vector2(-30.0, -26.0)) + 9.0, -26.0)
	var p1 := Vector3(-52.0, _ground_at(Vector2(-52.0, -56.0)) + 7.0, -56.0)
	var p2 := Vector3(-74.0, _ground_at(Vector2(-74.0, -64.0)) + 5.0, -64.0)
	var pos := p0 * (1.0 - u) * (1.0 - u) + p1 * 2.0 * u * (1.0 - u) + p2 * u * u
	var ahead_u := minf(u + 0.04, 1.0)
	var ahead := p0 * (1.0 - ahead_u) * (1.0 - ahead_u) \
		+ p1 * 2.0 * ahead_u * (1.0 - ahead_u) + p2 * ahead_u * ahead_u
	camera.global_position = pos
	camera.look_at(ahead - Vector3.UP * 1.5, Vector3.UP)


## Высота рельефа в точке XZ рейкастом вниз (высоко над самым высоким
## холмом); мимо мира — уровень моря.
func _ground_at(xz: Vector2) -> float:
	var from := Vector3(xz.x, 60.0, xz.y)
	var query := PhysicsRayQueryParameters3D.create(from, Vector3(xz.x, -5.0, xz.y))
	query.collide_with_areas = false
	var hit := get_tree().root.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.has("position"):
		return (hit["position"] as Vector3).y
	return 0.0


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
	Log.info("SNAP-DBG %s world_time=%.1f" % [file_name, Session.world_time], "World")
	var image := get_viewport().get_texture().get_image()
	var path: String = Dev.shot_dir.path_join(file_name)
	image.save_png(path)
	Log.info("Скриншот сохранён: " + path, "World")


## Замер FPS (П5.9 блок 9, SHOT_FPS): ждём SHOT_FPS_WAIT (по умолчанию 8 с)
## входа других участников (боты подключаются через ~1 с после старта),
## затем seconds секунд копим кадровые интервалы и печатаем статистику:
## среднее/медиана/минимум FPS, число участников в мире и нагрузку кадра.
## Числа на llvmpipe относительные — сравнение режимов, а не абсолют.
func _fps_probe(seconds: float) -> void:
	var wait := 8.0
	if not OS.get_environment("SHOT_FPS_WAIT").is_empty():
		wait = maxf(0.0, OS.get_environment("SHOT_FPS_WAIT").to_float())
	await get_tree().create_timer(wait).timeout
	var players_in_world := 0
	for peer_id: int in Net.players.keys():
		if bool(Net.players[peer_id].get("in_world", false)):
			players_in_world += 1
	var tier := GraphicsQuality.tier_from_settings()
	var tier_name := "NORMAL"
	match tier:
		GraphicsQuality.Tier.SIMPLE:
			tier_name = "SIMPLE"
		GraphicsQuality.Tier.HIGH:
			tier_name = "HIGH"
	print("FPS-PROBE: start seconds=%s players_in_world=%d quality=%s"
		% [str(seconds), players_in_world, tier_name])
	var deltas: Array[float] = []
	var prev_usec := Time.get_ticks_usec()
	var deadline_usec := prev_usec + int(seconds * 1_000_000.0)
	while Time.get_ticks_usec() < deadline_usec:
		await get_tree().process_frame
		var now_usec := Time.get_ticks_usec()
		var frame_ms := float(now_usec - prev_usec) / 1000.0
		prev_usec = now_usec
		if frame_ms > 0.0 and frame_ms < 1000.0:
			deltas.append(frame_ms)
	print("FPS-PROBE: zone=%s frames=%d primitives=%d draw_calls=%d"
		% [_island.zone_name_at(_player.global_position), deltas.size(),
			get_viewport().get_render_info(
				Viewport.RENDER_INFO_TYPE_VISIBLE,
				Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
			get_viewport().get_render_info(
				Viewport.RENDER_INFO_TYPE_VISIBLE,
				Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)])
	if deltas.is_empty():
		print("FPS-PROBE: FAIL — нет кадров")
		return
	var sorted_ms := deltas.duplicate()
	sorted_ms.sort()
	var total_ms := 0.0
	for ms: float in deltas:
		total_ms += ms
	var median_ms: float = sorted_ms[sorted_ms.size() / 2]
	var worst_ms: float = sorted_ms[sorted_ms.size() - 1]
	# p95 по кадрам (не по времени): устойчивее к одиночным выбросам.
	var p95_ms: float = sorted_ms[mini(
		sorted_ms.size() - 1, int(roundf(sorted_ms.size() * 0.95)))]
	print("FPS-PROBE: avg=%.1f median=%.1f p95=%.1f min=%.1f worst_ms=%.0f"
		% [1000.0 / (total_ms / deltas.size()), 1000.0 / median_ms,
			1000.0 / p95_ms, 1000.0 / worst_ms, worst_ms])


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
