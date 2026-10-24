# Сцена мира (раздел 6 SPEC): остров из gameplay/world/island.tscn
# (сгенерирован tools/generate_island.gd, коммитится — по сети не передаётся),
# игроки, мобы (в острове), цикл дня (DayCycle), карта (M), HUD.
# Спавн — на Площади или в зоне --dev-spawn. «Простая графика» (раздел 15):
# без теней, ближе туман и дальность камеры — флаг --simple-graphics
# (экран настроек — П8). По сети (раздел 10): снапшоты локального игрока
# шлёт Net, чужие игроки — RemotePlayer по снапшотам хоста, вход в идущий
# мир — world_state. Проксимити-очки Interactions (раздел 13) — тик раз
# в секунду по позициям ремоутов.
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
## Пауза тика проксимити Interactions (раздел 13: «секунда рядом»), с.
const PROXIMITY_TICK: float = 1.0
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
var _proximity_accum: float = 0.0


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
				peer_id, str(Net.players[peer_id]["name"]),
				Net._slot_appearance_bytes(peer_id)
			)


func _on_peer_joined_world(peer_id: int, player_name: String,
		appearance: PackedByteArray) -> void:
	if peer_id == Net.local_peer_id or _remotes.has(peer_id):
		return
	var remote := RemotePlayer.new()
	remote.setup(peer_id, player_name, appearance)
	add_child(remote)
	# Частицы из-под ног чужого игрока — по тем же покрытиям острова (П9).
	remote.setup_foot_fx(_island.art())
	_remotes[peer_id] = remote
	Log.info(
		"Игрок «%s» (peer %d, внешность %s) появился в мире"
		% [player_name, peer_id, appearance], "World"
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
	get_tree().call_deferred("change_scene_to_file", Dev.menu_scene_path())


func _on_host_lost(_reason: String) -> void:
	# Хост вышел: мир закрылся у всех; экран «Встречи» на его месте — П7.
	_exit_to_menu()


func _spawn_player() -> void:
	_player = PLAYER_SCENE.instantiate() as Player
	_player.position = _island.spawn_point(Session.spawn_zone)
	add_child(_player)
	# Внешность локального игрока — собранная в редакторе внешности (П5.8,
	# часть B; сохранение в user://, дефолт — мужское тело). Цвет верхней
	# одежды по хэшу id (раздел 16): в Steam-режиме — Steam id, в ENet и без
	# сети — peer id. Хэш локальный, по сети не передаётся.
	var own_id: int = SteamService.steam_id if SteamService.steam_id != 0 \
		else Net.local_peer_id
	var appearance := Save.load_appearance()
	_player.visual.setup_appearance(appearance)
	_player.visual.setup_palette(own_id)
	Log.info(
		"Внешность: пол %d, причёска %d, цвет %d (id=%d)" % [
			appearance.gender, appearance.hair,
			CharacterModel.palette_index(own_id), own_id],
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
## (--selftest-anim): герой Born Unblessed (П10) — AnimSelfCheckBU (позы
## костей покой/ходьба, резолв дорожек библиотеки sword, скиннинг ног);
## прежняя модель блочного персонажа — AnimSelfCheck + физический
## лендинг-сценарий Д2 (бег, прыжок, 2 с после касания) и RealismCheck на
## всех комбинациях пол × наряд — скольжение стоп и диапазоны рук
## блокирующие, посадка одежды — известный дефект П5.8 (откат Д4),
## KNOWN-FAIL без падения кода возврата (закрывается П5.10–П5.11).
## Печатает SELFTEST-ANIM: PASS/FAIL и выходит (код 1 при FAIL); гоняется
## и на экспортированных сборках, чтобы ловить проблемы экспорта.
func _selftest_anim(visual: CharacterVisual) -> void:
	for i: int in 40:
		await get_tree().physics_frame
	if visual is HeroModelBU:
		await _selftest_anim_bu(visual as HeroModelBU)
		return
	var result: Dictionary = await AnimSelfCheck.run(visual as CharacterModel, true)
	var reasons: PackedStringArray = PackedStringArray()
	if not result["ok"]:
		for reason: String in result["reasons"]:
			reasons.append(reason)
	# Приземление с зажатым движением (Д2, этап 0): физический сценарий
	# на локальном игроке — бег, прыжок, 2 с после касания; блокирующий.
	print("SELFTEST-ANIM: приземление на бегу (сценарий Д2 этапа 0)")
	var landing: Dictionary = await RealismCheck.check_landing_blend(
		_player, "run", true)
	if not landing["ok"]:
		for reason: String in landing["reasons"]:
			reasons.append(reason)
	# П5.8 этап 0: блоки реалистичности раздельно. Скольжение стоп и руки —
	# блокирующие. Посадка одежды (посадка тела «по одежде» отката Д4) —
	# известный дефект П5.8, закрывается П5.10–П5.11: печатается
	# KNOWN-FAIL и не роняет код возврата (пороги чекера не ослаблены).
	var model_scene := load("res://gameplay/player/character_model.tscn") \
		as PackedScene
	for gender: int in Appearance.GENDERS:
		for outfit: int in Appearance.OUTFITS.size():
			var model := model_scene.instantiate() as CharacterModel
			add_child(model)
			var ap := Appearance.default_for(gender)
			ap.top = outfit
			ap.legs = outfit
			ap.feet = outfit
			model.setup_appearance(ap)
			print("SELFTEST-ANIM: пол %d наряд %s" % [gender,
				Appearance.OUTFITS[outfit]])
			var feet: Dictionary = await RealismCheck.check_foot_slide(model)
			if not feet["ok"]:
				for reason: String in feet["reasons"]:
					reasons.append(reason)
			var arms: Dictionary = RealismCheck.check_arms(model)
			if not arms["ok"]:
				for reason: String in arms["reasons"]:
					reasons.append(reason)
			var fit: Dictionary = RealismCheck.check_body_fit(model)
			if not fit["ok"]:
				print("SELFTEST-ANIM: KNOWN-FAIL (известный дефект П5.8 → "
					+ "закрывается П5.10–П5.11, см. STATUS.md): посадка одежды")
				for reason: String in fit["reasons"]:
					print("  KNOWN-FAIL: %s" % reason)
			model.set_state(Protocol.AnimState.IDLE)
			model.queue_free()
	if reasons.is_empty():
		print("SELFTEST-ANIM: PASS")
		get_tree().quit(0)
		return
	print("SELFTEST-ANIM: FAIL")
	for reason: String in reasons:
		print("SELFTEST-ANIM: %s" % reason)
	get_tree().quit(1)


## Самопроверка героя Born Unblessed (--selftest-anim, П10): позы костей
## покой/ходьба, резолв всех дорожек библиотеки sword, скиннинг ног —
## всё блокирующее, KNOWN-FAIL нет. Отдельно от UBC-ветки: риг Mixamo,
## другие кости и клипы.
func _selftest_anim_bu(model: HeroModelBU) -> void:
	var result: Dictionary = await AnimSelfCheckBU.run(model, true)
	if result["ok"]:
		print("SELFTEST-ANIM: PASS")
		get_tree().quit(0)
		return
	print("SELFTEST-ANIM: FAIL")
	for reason: String in result["reasons"]:
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
	# SHOT_TRIO=1 — кадры П5.7 блока 8: трое персонажей вместе (Лес днём,
	# костёр вечером), без общих облётов.
	if OS.get_environment("SHOT_TRIO") == "1":
		await _shot_p57_trio(camera)
		get_tree().quit()
		return
	# Съёмки финала П5.8: SHOT_CREW=1 — шесть SHOWCASE-персонажей вместе
	# (Лес днём, костёр вечером), SHOT_FOLK=1 — трое жителей на своих местах
	# на Площади. Игрока прячем: в кадрах — материалы для владельца.
	if OS.get_environment("SHOT_CREW") == "1" \
			or OS.get_environment("SHOT_FOLK") == "1":
		_player.visible = false
		if OS.get_environment("SHOT_CREW") == "1":
			await _shot_p58_crew(camera)
		else:
			_set_day_fraction(SHOT_DAY_FRACTION)
			await _shot_p58_folks(camera)
		get_tree().quit()
		return
	# Серии кадров для GIF (сборка — tools/make_gif.py): SHOT_FLY=1 —
	# пролёт камеры над Лесом; SHOT_CLIP=walk|run|jump|wave|sit (актёр —
	# SHOT_ACTOR=индекс Appearance.SHOWCASE) — анимации персонажа.
	# Длина — SHOT_SECONDS (по умолчанию 6), темп — SHOT_SERIES_FPS.
	if OS.get_environment("SHOT_FLY") == "1" \
			or not OS.get_environment("SHOT_CLIP").is_empty():
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


## Кадры П5.7 блока 8 (SPEC п. 8): три новых персонажа вместе — днём
## в Лесу (та же первая точка тура) и вечером у костра на Площади.
## SHOT_TRIO=1. Модели в цветах разных id (как в мире), центральная
## машет; лица к камере (модель в покое смотрит в +Z — look_at наводит
## −Z, поэтому цель отражается через позицию модели).
func _shot_p57_trio(camera: Camera3D) -> void:
	_set_day_fraction(SHOT_DAY_FRACTION)
	var point := P57_FOREST_POINTS[0]
	var ground := _ground_at(point)
	var yaw := deg_to_rad(P57_FOREST_YAWS[0])
	var eye := Vector3(point.x, ground + 1.5, point.y)
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	await _shot_trio_at(
		camera, eye + forward * 4.0, forward, "p57_trio_forest_day.png")
	# Вечер у костра (0.62 — сумерки сразу после заката, огонь читается):
	# тройка полукругом за костром, лица освещены огнём.
	_set_day_fraction(0.62)
	await get_tree().create_timer(0.4).timeout
	var fire := Vector3(0.5, 2.0, 2.5)
	await _shot_trio_at(
		camera, fire + Vector3(0.0, 0.7, 5.5), Vector3(0.0, 0.0, 1.0),
		"p57_trio_campfire_evening.png")


## Поставить трёх персонажей полукругом в точке (ноги на землю) лицом
## к камере и снять кадр. cam_pos/forward задают позицию камеры и
## направление «от камеры вглубь» (персонажи в 3/4 оборота друг к другу).
func _shot_trio_at(
	camera: Camera3D, cam_pos: Vector3, forward: Vector3, file_name: String
) -> void:
	var right := forward.cross(Vector3.UP).normalized()
	var ground := _ground_at(Vector2(cam_pos.x + forward.x * 2.5,
		cam_pos.z + forward.z * 2.5))
	var center := cam_pos + forward * 2.5
	var poses: Array[Vector3] = [
		center + right * 1.4 - forward * 0.45,
		center + forward * 0.35,
		center - right * 1.4 - forward * 0.45,
	]
	var ids: Array[int] = [11, 22, 33]  # три разных цвета палитры
	for i: int in poses.size():
		var model := CharacterModel.new()
		add_child(model)
		model.position = Vector3(poses[i].x, ground, poses[i].z)
		model.setup(i)
		model.setup_palette(ids[i])
		# Лицом к камере: look_at наводит локальную −Z, модель смотрит +Z.
		model.look_at(model.position * 2.0 - cam_pos, Vector3.UP)
		if i == 1:
			model.play_one_shot(Protocol.AnimState.WAVE, 1.2)
	camera.global_position = cam_pos + Vector3.UP * 0.4
	camera.look_at(center + Vector3.UP * 0.9, Vector3.UP)
	await get_tree().create_timer(0.9).timeout
	await _snap(camera, file_name)
	for child in get_children():
		if child is CharacterModel:
			child.queue_free()


## Места у костра (Area3D CampfireSeat на острове) в порядке нод сцены.
func _campfire_seats() -> Array[CampfireSeat]:
	var seats: Array[CampfireSeat] = []
	for node in _island.find_children("*", "CampfireSeat", true, false):
		seats.append(node as CampfireSeat)
	seats.sort_custom(
		func(a: Node, b: Node) -> bool: return a.get_index() < b.get_index())
	return seats


## Кадры финала П5.8: шесть персонажей Appearance.SHOWCASE — те же
## внешности, что в туре редактора (--shot-dir в appearance_editor).
## Днём — дуга полукругом в точке 1 Леса (центральный машет); вечером —
## у костра: трое сидят на дальних лавках (посадка как в игре, _sit_at),
## трое стоят полукругом за огнём, лица освещены пламенем.
func _shot_p58_crew(camera: Camera3D) -> void:
	_set_day_fraction(SHOT_DAY_FRACTION)
	await get_tree().create_timer(0.4).timeout
	var point := P57_FOREST_POINTS[0]
	var ground := _ground_at(point)
	var yaw := deg_to_rad(P57_FOREST_YAWS[0])
	var eye := Vector3(point.x, ground + 1.5, point.y)
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	await _shot_crew_at(
		camera, eye + forward * 5.0, forward, "p58_crew_forest_day.png", false)
	_set_day_fraction(0.62)
	await get_tree().create_timer(0.4).timeout
	await _shot_crew_at(
		camera, Vector3(0.5, 2.9, 10.0), Vector3(0.0, 0.0, -1.0),
		"p58_crew_campfire_evening.png", true)


## Поставить шестерых SHOWCASE и снять кадр. Без сидения — дугой ±44°
## лицом к камере, центральный машет; seated — 0/2/4 сидят на лавках
## Seat5/6/7 (дальняя дуга), 1/3/5 стоят полукругом за костром.
func _shot_crew_at(
		camera: Camera3D, cam_pos: Vector3, forward: Vector3,
		file_name: String, seated: bool) -> void:
	var models: Array[CharacterModel] = []
	for i: int in Appearance.SHOWCASE.size():
		var model := CharacterModel.new()
		add_child(model)
		model.setup_appearance(
			Appearance.from_bytes(Appearance.SHOWCASE[i]))
		models.append(model)
	if seated:
		var seats := _campfire_seats()
		var seat_indices: Array[int] = [4, 5, 6]  # Seat5/6/7 — дальняя дуга
		for k: int in seat_indices.size():
			var seat := seats[seat_indices[k]]
			var model := models[k * 2]
			var to_fire := seat.face_target - seat.global_position
			to_fire.y = 0.0
			var dir := to_fire.normalized()
			model.global_position = seat.global_position + dir * 0.75 \
				- Vector3(0.0, B.campfire_seat_floor, 0.0)
			model.rotation.y = atan2(dir.x, dir.z)
			model.set_state(Protocol.AnimState.SIT)
		# Стоящие — по флангам позади сидящих (не перекрывают их), лицом
		# к камере сквозь огонь.
		var fire := Vector3(0.5, 0.0, 2.5)
		var stand_angles: Array[float] = [-0.5, 0.0, 0.5]
		for k: int in stand_angles.size():
			var model := models[k * 2 + 1]
			var ang := PI + stand_angles[k]
			var pos := fire + Vector3(sin(ang), 0.0, cos(ang)) * 4.6
			model.global_position = Vector3(
				pos.x, _ground_at(Vector2(pos.x, pos.z)), pos.z)
			model.look_at(model.global_position * 2.0 - cam_pos, Vector3.UP)
	else:
		# Ширина дуги — шаг ~1.3 м между соседями: шесть силуэтов читаются
		# по отдельности, а не сливаются в толпу.
		var right := forward.cross(Vector3.UP).normalized()
		var center := cam_pos + forward * 8.0
		var ground := _ground_at(Vector2(center.x, center.z))
		for i: int in models.size():
			var model := models[i]
			var t := 0.5 if models.size() == 1 else float(i) / float(models.size() - 1)
			var ang := (t - 0.5) * deg_to_rad(88.0)
			var pos := center + right * (sin(ang) * 5.2) \
				- forward * (cos(ang) * 1.6)
			model.global_position = Vector3(pos.x, ground, pos.z)
			model.look_at(model.global_position * 2.0 - cam_pos, Vector3.UP)
			if i == 2:
				model.play_one_shot(Protocol.AnimState.WAVE, 2.4)
	camera.global_position = cam_pos
	camera.look_at(cam_pos + forward * 6.0 + Vector3.UP * 0.6, Vector3.UP)
	await get_tree().create_timer(0.9).timeout
	await _snap(camera, file_name)
	for model: CharacterModel in models:
		model.queue_free()


## Трое жителей на своих местах (часть E): общий план Площади со всеми
## тремя и крупный кадр каждого (позы свои — Тимьян сидит на пеньке).
func _shot_p58_folks(camera: Camera3D) -> void:
	await get_tree().create_timer(0.4).timeout
	var folks: Array[Townsfolk] = []
	for node in get_tree().get_nodes_in_group(Townsfolk.TOWNSFOLK_GROUP):
		folks.append(node as Townsfolk)
	folks.sort_custom(
		func(a: Townsfolk, b: Townsfolk) -> bool: return a.character < b.character)
	if folks.size() != 3:
		push_error("ожидали трёх жителей, найдено %d" % folks.size())
		get_tree().quit()
		return
	var names: PackedStringArray = ["finn", "lumi", "thyme"]
	var center := Vector3.ZERO
	for folk: Townsfolk in folks:
		center += folk.global_position
	center /= folks.size()
	var spread := 0.0
	for folk: Townsfolk in folks:
		spread = maxf(spread, folk.global_position.distance_to(center))
	# Общий план: сбоку от линии крайних жителей, все трое в кадре.
	var line := folks[0].global_position - folks[2].global_position
	line.y = 0.0
	var cam_dir := line.normalized().cross(Vector3.UP).normalized()
	var cam_pos := center + cam_dir * clampf(spread * 2.2, 8.0, 24.0) \
		+ Vector3.UP * clampf(spread * 0.9, 3.0, 10.0)
	camera.global_position = cam_pos
	camera.look_at(center + Vector3.UP * 0.8, Vector3.UP)
	await _snap(camera, "p58_folks_plaza.png")
	for i: int in folks.size():
		var folk := folks[i]
		var pos := folk.global_position
		var look := Vector3(sin(folk.rotation.y), 0.0, cos(folk.rotation.y))
		var side := look.cross(Vector3.UP).normalized()
		var close := pos + look * 2.4 + side * 1.1 + Vector3.UP * 1.15
		camera.global_position = Vector3(close.x, pos.y + 1.15, close.z)
		camera.look_at(pos + Vector3.UP * 0.95, Vector3.UP)
		await _snap(camera, "p58_folk_%s.png" % names[i])


## Серии кадров финала П5.8 (GIF — tools/make_gif.py): SHOT_FLY=1 — пролёт
## над Лесом; SHOT_CLIP=walk|run|jump|wave|sit (+ SHOT_ACTOR=0..5, длина
## SHOT_SECONDS) — анимации персонажа. Время мира остановлено
## (Engine.time_scale = 0: часы, ландшафт стоят; шейдерный огонь и вода
## на TIME — живут), поза и траектория — чистые функции кадра, клипы
## продвигаются advance_preview на шаг 1/SHOT_SERIES_FPS: рваный темп
## рендера llvmpipe не ломает равномерность фаз.
func _shot_p58_series(camera: Camera3D) -> void:
	var fly := OS.get_environment("SHOT_FLY") == "1"
	var clip_name := OS.get_environment("SHOT_CLIP")
	var seconds := 8.0 if fly else 6.0
	match clip_name:
		"run":
			seconds = 5.0
		"forest_walk":
			seconds = 10.0
	if not OS.get_environment("SHOT_SECONDS").is_empty():
		seconds = clampf(
			OS.get_environment("SHOT_SECONDS").to_float(), 2.0, 12.0)
	var frames := int(roundf(seconds * SHOT_SERIES_FPS))
	if fly:
		_set_day_fraction(SHOT_DAY_FRACTION)
		await get_tree().create_timer(0.6).timeout
		await _record_series(camera, "fly_forest", frames,
			func(i: int, _t: float) -> void:
				_fly_forest_frame(camera, float(i) / float(frames)))
		return
	match clip_name:
		"sit":
			_set_day_fraction(0.62)
		_:
			_set_day_fraction(SHOT_DAY_FRACTION)
	await get_tree().create_timer(0.6).timeout
	var actor_index := 0
	if not OS.get_environment("SHOT_ACTOR").is_empty():
		actor_index = clampi(OS.get_environment("SHOT_ACTOR").to_int(),
			0, Appearance.SHOWCASE.size() - 1)
	var model := CharacterModel.new()
	add_child(model)
	model.setup_appearance(
		Appearance.from_bytes(Appearance.SHOWCASE[actor_index]))
	model.set_state(Protocol.AnimState.IDLE)
	model.advance_preview(0.5)  # бленд от rest-позы успевает устояться
	match clip_name:
		"walk":
			await _record_series(camera, "clip_walk", frames,
				func(_i: int, t: float) -> void:
					_walk_frame(camera, model, t))
		"forest_walk":
			await _record_series(camera, "clip_forest_walk", frames,
				func(_i: int, t: float) -> void:
					_forest_walk_frame(camera, model, t, seconds))
		"run":
			await _record_series(camera, "clip_run", frames,
				func(_i: int, t: float) -> void:
					_run_circle_frame(camera, model, t))
		"jump":
			await _record_series(camera, "clip_jump", frames,
				func(_i: int, t: float) -> void:
					_jump_frame(camera, model, t))
		"wave":
			await _record_series(camera, "clip_wave", frames,
				func(_i: int, t: float) -> void:
					_wave_frame(camera, model, t))
		"sit":
			var partner := CharacterModel.new()
			add_child(partner)
			partner.setup_appearance(
				Appearance.from_bytes(Appearance.SHOWCASE[(actor_index + 3)
					% Appearance.SHOWCASE.size()]))
			var seats := _campfire_seats()
			_seat_model_at(partner, seats[7])  # соседняя лавка, сидит с начала
			partner.set_state(Protocol.AnimState.SIT)
			await _record_series(camera, "clip_sit", frames,
				func(_i: int, t: float) -> void:
					_sit_frame(camera, model, seats[0], t))
			partner.queue_free()
		_:
			push_error("неизвестный SHOT_CLIP: " + clip_name)
	model.queue_free()


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


## Прямая «южная» дорожка Площади для ходьбы и прыжков (мимо лавок
## костра): от запада к востоку, камера южнее — в кадре персонаж и костёр.
const CLIP_PATH_Z: float = 9.2
const CLIP_PATH_HALF: float = 7.6
const CLIP_CAM_Z: float = 13.4


## Ходьба по прямой (walk_speed 2.5): позиция от времени, камера следит
## с юга, модель повёрнута по ходу (+X: atan2(1, 0) = PI/2 — модель
## смотрит +Z, yaw 90° разворачивает её на восток).
func _walk_frame(camera: Camera3D, model: CharacterModel, t: float) -> void:
	var x := clampf(-7.5 + 2.5 * t, -CLIP_PATH_HALF, CLIP_PATH_HALF)
	var ground := _ground_at(Vector2(x, CLIP_PATH_Z))
	model.global_position = Vector3(x, ground, CLIP_PATH_Z)
	model.rotation.y = PI / 2.0
	model.set_state(Protocol.AnimState.WALK)
	model.advance_preview(1.0 / SHOT_SERIES_FPS)
	camera.global_position = Vector3(0.0, ground + 1.35, CLIP_CAM_Z)
	camera.look_at(model.global_position + Vector3.UP * 1.0, Vector3.UP)


## Прогулка по Лесу (П5.9 блок 8, GIF «прогулка по Лесу»): модель идёт
## от опушки к Площади вглубь леса по кривой Безье между точками 1–3 тура
## П5.7 (хорда ~26 м за 10 с ≈ темп ходьбы). Камера следует сзади-сбоку.
const FOREST_WALK_P0 := Vector2(-36.0, -44.0)
const FOREST_WALK_P1 := Vector2(-50.0, -54.0)
const FOREST_WALK_P2 := Vector2(-60.0, -64.0)


## Точка пути Леса на доле u [0, 1] (Безье по XZ, высота — рельеф).
func _forest_walk_at(u: float) -> Vector3:
	var p := FOREST_WALK_P0 * (1.0 - u) * (1.0 - u) \
		+ FOREST_WALK_P1 * 2.0 * u * (1.0 - u) \
		+ FOREST_WALK_P2 * u * u
	return Vector3(p.x, _ground_at(p), p.y)


func _forest_walk_frame(
		camera: Camera3D, model: CharacterModel, t: float, seconds: float
) -> void:
	var u := clampf(t / seconds, 0.0, 1.0)
	var pos := _forest_walk_at(u)
	var ahead := _forest_walk_at(minf(u + 0.02, 1.0))
	var tangent := (ahead - pos)
	tangent.y = 0.0
	tangent = tangent.normalized()
	model.global_position = pos
	model.rotation.y = atan2(tangent.x, tangent.z)
	model.set_state(Protocol.AnimState.WALK)
	model.advance_preview(1.0 / SHOT_SERIES_FPS)
	# Сзади-сбоку: позади по пути, на метр правее, взгляд чуть вперёд модели.
	var right := tangent.cross(Vector3.UP).normalized()
	camera.global_position = _forest_walk_at(maxf(u - 0.06, 0.0)) \
		+ Vector3.UP * 1.5 + right * 1.1
	camera.look_at(pos + Vector3.UP * 1.15 + tangent * 0.6, Vector3.UP)


## Бег по кругу вокруг костра (run_speed 6.5, радиус за лавками): модель
## дважды проходит мимо камеры, костёр и площадь в кадре; поворот — по
## касательной к кругу.
const CLIP_RUN_RADIUS: float = 6.4
const CLIP_RUN_SPEED: float = 6.5


func _run_circle_frame(camera: Camera3D, model: CharacterModel, t: float) -> void:
	var center := Vector2(0.5, 2.5)
	var ang := PI / 2.0 + CLIP_RUN_SPEED * t / CLIP_RUN_RADIUS
	var here := center + Vector2(cos(ang), -sin(ang)) * CLIP_RUN_RADIUS
	var prev_ang := ang + 0.02
	var prev := center + Vector2(cos(prev_ang), -sin(prev_ang)) * CLIP_RUN_RADIUS
	var dir := (here - prev).normalized()
	var ground := _ground_at(here)
	model.global_position = Vector3(here.x, ground, here.y)
	model.rotation.y = atan2(dir.x, dir.y)
	model.set_state(Protocol.AnimState.RUN)
	model.advance_preview(1.0 / SHOT_SERIES_FPS)
	var cam_ground := _ground_at(Vector2(0.5, CLIP_CAM_Z))
	camera.global_position = Vector3(0.5, cam_ground + 2.1, CLIP_CAM_Z)
	camera.look_at(model.global_position + Vector3.UP * 1.0, Vector3.UP)


## Два прыжка с разбегом (3 м/с, прыжок v0 = 7.5, g = 20 — высота ~1.4 м,
## полёт 0.75 с, как в игре): разбег → прыжок → приземление/пауза →
## второй разбег и прыжок. Кусочный тайминг ниже; камера следит с юга.
const CLIP_JUMP_V0: float = 7.5
const CLIP_JUMP_G: float = 20.0


func _jump_pose(t: float) -> Dictionary:
	# Возвращает {x, y_off, state} по кускам пути (t = 0.7 и 3.3 — прыжки).
	if t < 0.7:  # разбег
		return {"x": -5.5 + 3.0 * t, "y": 0.0, "state": Protocol.AnimState.RUN}
	if t < 1.45:  # первый прыжок
		return _jump_arc(t - 0.7, -3.4)
	if t < 2.6:  # приземление и пауза
		return {"x": -1.15, "y": 0.0,
			"state": Protocol.AnimState.LAND if t < 2.0
				else Protocol.AnimState.IDLE}
	if t < 3.3:  # второй разбег
		return {"x": -1.15 + 3.0 * (t - 2.6), "y": 0.0,
			"state": Protocol.AnimState.RUN}
	if t < 4.05:  # второй прыжок
		return _jump_arc(t - 3.3, 0.95)
	return {"x": 3.2, "y": 0.0,
		"state": Protocol.AnimState.LAND if t < 4.6
			else Protocol.AnimState.IDLE}


func _jump_arc(tau: float, x0: float) -> Dictionary:
	var state := Protocol.AnimState.FALL
	if tau < 0.18:
		state = Protocol.AnimState.JUMP
	elif tau >= 0.72:
		state = Protocol.AnimState.LAND
	return {"x": x0 + 3.0 * tau,
		"y": CLIP_JUMP_V0 * tau - CLIP_JUMP_G * tau * tau * 0.5,
		"state": state}


func _jump_frame(camera: Camera3D, model: CharacterModel, t: float) -> void:
	var pose := _jump_pose(t)
	var ground := _ground_at(Vector2(pose["x"], CLIP_PATH_Z))
	model.global_position = Vector3(pose["x"], ground + pose["y"], CLIP_PATH_Z)
	model.rotation.y = PI / 2.0
	model.set_state(pose["state"])
	model.advance_preview(1.0 / SHOT_SERIES_FPS)
	camera.global_position = Vector3(0.0, ground + 1.3, CLIP_CAM_Z)
	camera.look_at(model.global_position + Vector3.UP * 1.0, Vector3.UP)


## Взмахи «Привет!» у костра: окна 0.6–2.6 и 3.2–5.2 с, между ними покой
## (метка wave_window не даёт перезапускать клип каждый кадр).
func _wave_frame(camera: Camera3D, model: CharacterModel, t: float) -> void:
	var pos := Vector3(3.4, _ground_at(Vector2(3.4, 8.2)), 8.2)
	model.global_position = pos
	model.rotation.y = 0.0  # модель в покое смотрит +Z — лицом к камере
	var window := -1
	if t >= 0.6 and t < 2.6:
		window = 0
	elif t >= 3.2 and t < 5.2:
		window = 1
	var current: int = model.get_meta("wave_window", -1)
	if window >= 0 and current != window:
		model.set_meta("wave_window", window)
		model.play_one_shot(Protocol.AnimState.WAVE, 2.0)
	elif window < 0 and current != -1:
		model.set_meta("wave_window", -1)
	model.set_state(Protocol.AnimState.IDLE)
	model.advance_preview(1.0 / SHOT_SERIES_FPS)
	camera.global_position = pos + Vector3(1.1, 1.25, 3.1)
	camera.look_at(pos + Vector3.UP * 1.05, Vector3.UP)


## Сесть у костра (вечер): секунда стоя перед лавкой, затем поза сидения
## (бленд 0.15 с — плавный переход), рядом уже сидит второй персонаж.
func _sit_frame(
		camera: Camera3D, model: CharacterModel, seat: CampfireSeat, t: float) -> void:
	if t >= 1.0:
		_seat_model_at(model, seat)
		model.set_state(Protocol.AnimState.SIT)
	else:
		var to_fire := seat.face_target - seat.global_position
		to_fire.y = 0.0
		var dir := to_fire.normalized()
		model.global_position = seat.global_position + dir * 1.1 \
			- Vector3(0.0, B.campfire_seat_floor * 0.4, 0.0)
		model.rotation.y = atan2(dir.x, dir.z)
		model.set_state(Protocol.AnimState.IDLE)
	model.advance_preview(1.0 / SHOT_SERIES_FPS)
	var pos := seat.global_position
	camera.global_position = pos + Vector3(2.9, 1.35, 2.2)
	camera.look_at(pos + Vector3(-0.4, 0.55, -0.4), Vector3.UP)


## Посадить модель на место как в игре (player._sit_at): origin на землю
## перед лавкой, лицом к огню.
func _seat_model_at(model: CharacterModel, seat: CampfireSeat) -> void:
	var to_fire := seat.face_target - seat.global_position
	to_fire.y = 0.0
	var dir := to_fire.normalized()
	model.global_position = seat.global_position + dir * 0.75 \
		- Vector3(0.0, B.campfire_seat_floor, 0.0)
	model.rotation.y = atan2(dir.x, dir.z)


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
