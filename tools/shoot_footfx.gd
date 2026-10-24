extends SceneTree
## Съёмка частиц шагов FootFx (переделка П9 по замечанию владельца) под
## xvfb/llvmpipe. Игрок настоящим путём входит в мир (--bot), затем по
## найденным на запечённом острове отрезкам травы/грязи/лужи/камня идёт
## и бежит, кадры пишутся серией.
##
## Уроки прогонов 24.10 (кадры выходили бут-экраном, мир не доезжал до
## пикселей): под opengl3/llvmpipe фоновый рендер мира катастрофически
## отстаёт (первый кадр мира рендерился >10 мин и не завершился), а
## get_image() без синхронизации возвращает ЗАВЕРШИВШИЙСЯ кадр — то есть
## бут-экран. Поэтому здесь:
##   1) RenderingServer.render_loop_enabled = false в момент появления
##      мира — фоновые кадры не жуют llvmpipe впустую (бут-флоу не ждёт
##      отрисовку — проверено grep'ом);
##   2) каждый снимок — RenderingServer.force_draw(true): ровно один
##      синхронный рендер, пиксели всегда текущие, отставания нет;
##   3) камера «у ног» — НЕ вторая камера (make_current() рендер под
##      llvmpipe игнорирует — вывод tools/diag_series_cam.gd), а перенос
##      собственной камеры игрока (top_level + позиция каждый кадр);
##   4) вид у ног — сбоку от игрока, в сторону суши (высота земли через
##      40 м от ноги), чтобы в кадр не попал океан (шейдер воды под
##      llvmpipe — главный подозреваемый зависаний);
##   5) игрок телепортируется на первый отрезок ещё ДО отпускания экрана
##      загрузки — первый кадр мира рендерится на дешёвом виде (трава),
##      а не на тяжёлой Площади со спавна.
## Замедление адаптивное: time_scale = TARGET_SIM / фактическое время
## итерации — симуляции на кадр проходит ~0.12 с (7 физических тиков,
## меньше предела 8): анимация прыгает не дальше контакта стопы, порции
## (жизнь 0.55 с) живут 4-5 кадров и попадают в кадр в полёте. В имени
## кадра — «возраст» последней порции: b0 — порция в этом кадре, b1/b2 —
## кадр-два спустя, b3 — давно.
## Сырая серия — в builds/screenshots/footfx_raw (не в git); отобранные
## кадры и склейки кладутся в docs/screenshots/footfx после просмотра.
## В конец серии добавлены сцены «было» (before_*): реконструкция старого
## RunParticles из П9 (beb4850) — непрерывный поток комьев 8 см, альфа
## 0.9, на камне крошка — для пар «было–стало»; новый FootFx в этих
## сценах спрятан. Текстура stone.png удалена из репо — передаётся путём
## (второй позиционный аргумент, восстановлена из git-lfs).
## Запуск:
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 -s res://tools/shoot_footfx.gd -- --bot \
##     <каталог> [путь/stone.png]
## Выход: 0 — все сцены сняты; 3 — мир не достигнут; 4 — не задан каталог;
##   5 — лимит времени, серия неполная (снятое сохранено).

const ART: IslandArt = preload("res://gameplay/world/island_art.res")
const B: Balance = preload("res://gameplay/balance.tres")
## Текстуры «было»: dirt/grass живут в репо, stone передаётся путём.
const LEGACY_DIRT_TEX: Texture2D = preload("res://assets/vfx/particles/dirt.png")
const LEGACY_GRASS_TEX: Texture2D = preload("res://assets/vfx/particles/grass.png")

## Параметры «было» — дословно из beb4850 (balance.gd + run_particles.gd):
## непрерывная эмиссия, 26 частиц, жизнь 0.45 с, комья 0.08 м (масштаб
## 0.6–1.3 → до 10 см), скорость 0.44–1.1 м/с, разброс 40°, гравитация
## −9, альфа 0.9, доля эмиссии pow((v−0.3)/(6.5−0.3), 1.6).
const LEGACY_AMOUNT: int = 26
const LEGACY_LIFETIME: float = 0.45
const LEGACY_SIZE: float = 0.08
const LEGACY_SPEED: float = 1.1
const LEGACY_SPREAD: float = 40.0
const LEGACY_ALPHA: float = 0.9

## Симуляции на кадр: контакт стопы длится ~0.1 с, прыжок анимации больше
## этого шага теряет пересечения порога; 0.12 с = 7 тиков физики (< 8).
const TARGET_SIM_PER_SHOT: float = 0.12
## Стартовое замедление до калибровки (первая итерация всегда медленная).
const TS_INIT: float = 0.004
const TS_MIN: float = 0.0002
const TS_MAX: float = 0.05
## Кадров на сцену: 8 × 0.12 с ≈ 1 с симуляции — 2-3 шага бегом, 1-2
## шагом, порция видна в 4-5 кадрах. Прыжок длиннее: разгон, фаза полёта
## и приземление ~1.2 с.
const FRAMES_PER_SCENE: int = 8
const FRAMES_PER_STRIP: int = 8
const FRAMES_PER_JUMP: int = 12
## Общий лимит прогона, мин (страховка: снятое сохраняется, выход 5).
const WALL_LIMIT_MIN: float = 200.0
## Проверяемая длина пробега, м: 8 кадров × 0.12 с × 5 м/с + разгон.
const SEGMENT_M: float = 12.0
## Минимальная высота земли отрезка: ниже — море/мелководье/лужа у воды.
const MIN_H: float = 0.45
## Максимальный уклон пробега (тангенс): круче — не пробег, а скольжение.
const MAX_SLOPE: float = 0.35
## Радиус вокруг Площади, где отрезки не ищем: там своё покрытие — гравий.
const PLAZA_AVOID: float = 32.0
## Камера «у ног»: в стороне от игрока, смотрит поперёк хода; сторона
## выбирается в глубину суши (земля через 40 м выше воды — иначе океан
## в кадре и шейдер воды в рендере).
const FEET_CAM_SIDE_M: float = 1.9
const FEET_CAM_AHEAD_M: float = 0.6
const FEET_CAM_H: float = 0.55
const FEET_CAM_FOV: float = 55.0
const INLAND_CHECK_M: float = 40.0

var _out: String = ""
var _legacy_stone_path: String = ""
var _legacy_stone_tex: Texture2D = null
var _legacy_fx: GPUParticles3D = null
var _legacy_proc: ParticleProcessMaterial = null
var _t: float = 0.0
var _world: Node3D = null
var _loading_seen: bool = false
var _player: Node3D = null
var _foot_fx: FootFx = null
## Сцены: name, seg, walk, cam ("game"/"feet"), jump, legacy.
var _scenes: Array[Dictionary] = []
var _segments: Dictionary = {}
var _scene_i: int = -1
var _frame_in_scene: int = 0
var _run_dir := Vector3(1.0, 0.0, 0.0)
var _cam_side := Vector3(0.0, 0.0, 1.0)
var _player_cam: Camera3D = null
var _player_cam_fov: float = 75.0
var _feet_cam_on: bool = false
var _base_steps: int = 0
var _scene_burst_base: int = 0
var _seen_bursts: int = 0
var _frames_since_burst: int = 99
var _wall0_msec: int = 0
var _shot_wall: int = 0


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			if _out.is_empty():
				_out = arg
			elif _legacy_stone_path.is_empty():
				_legacy_stone_path = arg
	if _out.is_empty():
		push_error("FOOTFX FAIL: не задан каталог PNG (аргумент после --)")
		quit(4)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	_wall0_msec = Time.get_ticks_msec()
	root.add_child((load("res://scenes/boot.tscn") as PackedScene).instantiate())
	print("FOOTFX: старт, кадры в %s" % _out)


func _process(delta: float) -> bool:
	_t += delta
	if _world == null:
		if not _loading_seen and LoadingScreenBU.current != null:
			_loading_seen = true
		var found: Node = root.find_child("WorldScene", true, false)
		if found != null:
			_world = found as Node3D
			_grab_player(found)
			# Фоновый рендер больше не нужен: дальше только наши force_draw.
			RenderingServer.render_loop_enabled = false
			_find_segments()
			# Ранний телепорт на первый отрезок: первый дорогой кадр мира
			# рендерится на дешёвом виде, а не на Площади спавна.
			for scene: Dictionary in _scenes:
				if not scene.get("legacy", false):
					_park_player(_segments[scene["seg"]])
					break
			print("FOOTFX: мир в кадре %.1f с, отрезков %d" % [_t, _segments.size()])
		elif _t > 240.0:
			print("FOOTFX FAIL: мир не достигнут")
			quit(3)
			return true
		return false
	if LoadingScreenBU.current != null:
		return false  # экран загрузки ещё держит вход
	if _scene_i < 0:
		_setup_scenes()
		return false
	return _run_scene()


func _grab_player(world: Node) -> void:
	var p: Node3D = world.get_node_or_null("Player")
	if p == null:
		return
	for bot: Node in p.find_children("*", "BotController", true, false):
		bot.queue_free()
	_player = p
	_foot_fx = p.get_node_or_null("FootFx") as FootFx
	var session: Node = root.get_node_or_null("Session")
	if session != null:
		session.set("bot", false)
	_player_cam = p.get_node_or_null(
		"CameraRig/Pivot/SpringArm/Camera3D") as Camera3D
	if _player_cam != null:
		_player_cam_fov = _player_cam.fov


## Поставить игрока в начало отрезка (без хода) — для раннего телепорта.
func _park_player(seg: Dictionary) -> void:
	if _player == null or seg.is_empty():
		return
	_player.velocity = Vector3.ZERO
	_player.global_position = seg["start"]
	var rig: Node3D = _player.get_node_or_null("CameraRig")
	if rig != null:
		var dir: Vector3 = seg["dir"]
		rig.rotation.y = atan2(-dir.x, -dir.z)
		rig.global_position = seg["start"] + Vector3.UP * 1.55


## Сценарии: ходьба/бег по покрытиям с частицами (трава, грязь, лужа,
## земля) — крупно у ног; камера игры — по одному представителю (бег по
## грязи и траве, шаг по грязе); камень — негативный случай (бег, частиц
## быть не должно); прыжок-приземление; лента подряд идущих кадров для
## склейки-«клипа»; «было»-реконструкции в конце.
func _find_segments() -> void:
	_segments["dirt"] = _plaza_segment()
	for key: String in ["grass", "mud", "puddle", "stone"]:
		_segments[key] = _find_segment(_kind_of(key))
		if _segments[key].is_empty():
			print("FOOTFX: отрезок %s не найден — сцены пропущены" % key)
	for key: String in ["grass", "mud", "puddle", "dirt"]:
		if _segments[key].is_empty():
			continue
		for speed: String in ["walk", "run"]:
			_scenes.append({"name": "%s_%s_feet" % [speed, key],
				"seg": key, "walk": speed == "walk",
				"cam": "feet", "jump": false})
	for extra: Dictionary in [
			{"name": "run_mud_game", "seg": "mud", "walk": false,
				"cam": "game", "jump": false},
			{"name": "run_grass_game", "seg": "grass", "walk": false,
				"cam": "game", "jump": false},
			{"name": "walk_mud_game", "seg": "mud", "walk": true,
				"cam": "game", "jump": false},
			{"name": "jump_dirt_feet", "seg": "dirt",
				"walk": false, "cam": "feet", "jump": true},
			{"name": "strip_mud_feet", "seg": "mud",
				"walk": false, "cam": "feet", "jump": false}]:
		if not _segments[extra["seg"]].is_empty():
			_scenes.append(extra)
	if not _segments["stone"].is_empty():
		_scenes.append({"name": "run_stone_feet", "seg": "stone",
			"walk": false, "cam": "feet", "jump": false})


func _setup_scenes() -> void:
	Engine.time_scale = TS_INIT
	# «Было» — в самый конец: главное (новый эффект) снимается первым.
	if not _legacy_stone_path.is_empty():
		var img := Image.load_from_file(_legacy_stone_path)
		if img != null:
			_legacy_stone_tex = ImageTexture.create_from_image(img)
			print("FOOTFX: stone.png «было» загружен из %s" % _legacy_stone_path)
		else:
			print("FOOTFX: stone.png «было» не читается: %s" % _legacy_stone_path)
	if not _segments["grass"].is_empty():
		_scenes.append({"name": "before_run_grass_feet", "seg": "grass",
			"walk": false, "cam": "feet", "jump": false, "legacy": true})
	if not _segments["stone"].is_empty() and _legacy_stone_tex != null:
		_scenes.append({"name": "before_run_stone_feet", "seg": "stone",
			"walk": false, "cam": "feet", "jump": false, "legacy": true})
	print("FOOTFX: сцен %d" % _scenes.size())
	# Калибровка: один синхронный кадр мира на первом виде + снимок для
	# самопроверки, что мир действительно в пикселях (а не бут-экран).
	_shot_wall = Time.get_ticks_msec()
	_force_shot("_calibration")
	_adapt_ts()
	_next_scene()


## Замер итерации → time_scale для следующего кадра: TARGET_SIM симуляции.
func _adapt_ts() -> void:
	var wall: float = (Time.get_ticks_msec() - _shot_wall) / 1000.0
	Engine.time_scale = clampf(TARGET_SIM_PER_SHOT / maxf(wall, 0.5),
		TS_MIN, TS_MAX)


func _kind_of(key: String) -> int:
	match key:
		"grass": return ForestGround.Surface.GRASS
		"mud": return ForestGround.Surface.MUD
		"puddle": return ForestGround.Surface.PUDDLE
		"stone": return ForestGround.Surface.STONE
	return ForestGround.Surface.DIRT


## Один кадр текущей сцены: следящая камера у ног, маркер «возраста»
## последней порции, синхронный снимок.
func _run_scene() -> bool:
	var scene: Dictionary = _scenes[_scene_i]
	if _frame_in_scene == 0:
		_teleport(scene)
		_frame_in_scene = 1
		return false
	if _frames_since_burst < 99:
		_frames_since_burst += 1
	if _foot_fx != null and _foot_fx.stats_bursts > _seen_bursts:
		_seen_bursts = _foot_fx.stats_bursts
		_frames_since_burst = 0
	if _feet_cam_on:
		_update_feet_cam()
	if scene["jump"] and _frame_in_scene == 2:
		Input.action_press("jump")
	elif scene["jump"] and _frame_in_scene == 3:
		Input.action_release("jump")
	if scene.get("legacy", false) == true:
		_update_legacy()
	_shot_wall = Time.get_ticks_msec()
	_force_shot("%s_f%02d_b%d" % [scene["name"], _frame_in_scene,
		mini(_frames_since_burst, 3)])
	_adapt_ts()
	_frame_in_scene += 1
	var frames: int = FRAMES_PER_STRIP \
		if String(scene["name"]).begins_with("strip_") else FRAMES_PER_SCENE
	if scene["jump"]:
		frames = FRAMES_PER_JUMP
	if _frame_in_scene > frames or _ran_past_segment():
		print("FOOTFX: %s — шагов %d, порций %d, кадр %.1f с" % [scene["name"],
			_foot_fx.stats_steps - _base_steps,
			_foot_fx.stats_bursts - _scene_burst_base,
			(Time.get_ticks_msec() - _shot_wall) / 1000.0])
		_next_scene()
	return false


## Страховка от медленных кадров: пробег длиннее отрезка — сцена кончена.
func _ran_past_segment() -> bool:
	if _player == null:
		return false
	var seg: Dictionary = _segments[_scenes[_scene_i]["seg"]]
	var travelled: float = (_player.global_position
		- seg["start"]).dot(_run_dir)
	return travelled > SEGMENT_M + 2.0


func _next_scene() -> void:
	Input.action_release("move_forward")
	Input.action_release("walk")
	Input.action_release("jump")
	_restore_player_cam()
	if _legacy_fx != null:
		_legacy_fx.queue_free()
		_legacy_fx = null
		_legacy_proc = null
	if _foot_fx != null:
		_foot_fx.visible = true
	_scene_i += 1
	_frame_in_scene = 0
	_frames_since_burst = 99
	if _scene_i >= _scenes.size():
		print("FOOTFX PASS: снято сцен %d за %.0f мин" % [
			_scenes.size(), (Time.get_ticks_msec() - _wall0_msec) / 60000.0])
		quit(0)
		return
	if (Time.get_ticks_msec() - _wall0_msec) / 60000.0 > WALL_LIMIT_MIN:
		print("FOOTFX PARTIAL: лимит времени, снято сцен %d из %d" % [
			_scene_i, _scenes.size()])
		quit(5)
		return
	if _foot_fx != null:
		_base_steps = _foot_fx.stats_steps
		_scene_burst_base = _foot_fx.stats_bursts
		_seen_bursts = _foot_fx.stats_bursts


## Поставить игрока в начало отрезка, развернуть камеру игрока по
## направлению пробега, зажать ход; сцене «у ног» — перенос камеры
## игрока сбоку от ног (см. шапку: вторая камера под llvmpipe не работает).
func _teleport(scene: Dictionary) -> void:
	var seg: Dictionary = _segments[scene["seg"]]
	var start: Vector3 = seg["start"]
	_run_dir = seg["dir"]
	_player.velocity = Vector3.ZERO
	_player.global_position = start
	var rig: Node3D = _player.get_node_or_null("CameraRig")
	if rig != null:
		rig.rotation.y = atan2(-_run_dir.x, -_run_dir.z)
		# Риг догоняет игрока лерпом несколько кадров — после телепорта
		# ставим его сразу, чтобы камера игры не летела через полострова.
		rig.global_position = start + Vector3.UP * 1.55
	if scene["cam"] == "feet":
		_hijack_player_cam()
	else:
		_restore_player_cam()
	if scene.get("legacy", false) == true:
		# Новый эффект спрятан — в кадре только реконструкция П9.
		if _foot_fx != null:
			_foot_fx.visible = false
		_build_legacy(_kind_of(scene["seg"]))
	Input.action_press("move_forward")
	if scene["walk"]:
		Input.action_press("walk")


## Камера «у ног»: собственная камера игрока отцепляется от руки
## (top_level) и ставится сбоку-чуть-впереди ног; каждый кадр — заново,
## поэтому кадр и камера согласованы даже при скачках позиции.
func _hijack_player_cam() -> void:
	if _player_cam == null:
		return
	_pick_inland_side()
	_player_cam.top_level = true
	_player_cam.fov = FEET_CAM_FOV
	_feet_cam_on = true
	_update_feet_cam()


## Сторона съёмки — в глубину суши: если через INLAND_CHECK_M от игрока
## в этой стороне море, снимаем с другой (океан не попадает в кадр).
func _pick_inland_side() -> void:
	var side := Vector3(-_run_dir.z, 0.0, _run_dir.x)
	var feet: Vector3 = _player.global_position
	var h_side: float = IslandGen.ground_height(
		ART.heights, feet.x + side.x * INLAND_CHECK_M,
		feet.z + side.z * INLAND_CHECK_M)
	var h_other: float = IslandGen.ground_height(
		ART.heights, feet.x - side.x * INLAND_CHECK_M,
		feet.z - side.z * INLAND_CHECK_M)
	_cam_side = side if h_side >= h_other else -side


func _restore_player_cam() -> void:
	_feet_cam_on = false
	if _player_cam == null:
		return
	if _player_cam.top_level:
		_player_cam.top_level = false
	_player_cam.fov = _player_cam_fov


func _update_feet_cam() -> void:
	if _player_cam == null:
		return
	var feet: Vector3 = _player.global_position
	var pos := feet + _run_dir * FEET_CAM_AHEAD_M + _cam_side * FEET_CAM_SIDE_M
	pos.y = maxf(feet.y + FEET_CAM_H,
		IslandGen.ground_height(ART.heights, pos.x, pos.z) + 0.35)
	_player_cam.global_position = pos
	_player_cam.look_at(feet + _run_dir * 0.4 + Vector3(0.0, 0.25, 0.0))


# --- Поиск отрезков покрытий на запечённом острове ---

## Отрезок: прямая SEGMENT_M метров одного покрытия, пологий уклон, земля
## выше воды. Возвращает {start, dir} или {}.
func _find_segment(kind: int) -> Dictionary:
	var dirs := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
	for z: int in range(-104, 104, 4):
		for x: int in range(-104, 104, 4):
			if Vector2(float(x), float(z)).distance_to(ForestGround.PLAZA_CENTER) < PLAZA_AVOID:
				continue
			if ForestGround.surface_kind(ART, Vector3(float(x), 0.0, float(z))) != kind:
				continue
			var h0: float = IslandGen.ground_height(ART.heights, float(x), float(z))
			if h0 < MIN_H:
				continue
			for dir: Vector2 in dirs:
				var ok := true
				for t: float in [4.0, 8.0, SEGMENT_M]:
					var px: float = float(x) + dir.x * t
					var pz: float = float(z) + dir.y * t
					if ForestGround.surface_kind(ART, Vector3(px, 0.0, pz)) != kind:
						ok = false
						break
					var h: float = IslandGen.ground_height(ART.heights, px, pz)
					if h < MIN_H or absf(h - h0) / t > MAX_SLOPE:
						ok = false
						break
				if ok:
					# Старт за 2 м до точки: пара кадров разгона до неё.
					var sx: float = float(x) - dir.x * 2.0
					var sz: float = float(z) - dir.y * 2.0
					print("FOOTFX: отрезок покрытия %d — старт (%.0f, %.0f), ход (%d, %d)" % [
						kind, sx, sz, int(dir.x), int(dir.y)])
					return {"start": Vector3(sx,
						IslandGen.ground_height(ART.heights, sx, sz) + 0.05, sz),
						"dir": Vector3(dir.x, 0.0, dir.y)}
	return {}


## Гравийная Площадь — заведомо ровная утоптанная земля.
func _plaza_segment() -> Dictionary:
	var c: Vector2 = ForestGround.PLAZA_CENTER
	var y: float = IslandGen.ground_height(ART.heights, c.x, c.y) + 0.05
	return {"start": Vector3(c.x - 8.0, y, c.y - 8.0),
		"dir": Vector3(1.0, 0.0, 1.0).normalized()}


# --- «Было»: реконструкция RunParticles из П9 (beb4850) ---

## Собрать старый эмиттер: непрерывный поток, комья 8 см, альфа 0.9.
## Пассы по покрытию — как в _refresh_surface() старого кода: камень —
## крошка, трава — комья + травинки, земля — комья. Эмиттер висит в мире
## (тождественный поворот): направление «назад-вверх» — от хода пробега.
func _build_legacy(kind: int) -> void:
	_legacy_fx = GPUParticles3D.new()
	_legacy_fx.name = "LegacyRunDust"
	_legacy_fx.amount = LEGACY_AMOUNT
	_legacy_fx.lifetime = LEGACY_LIFETIME
	_legacy_fx.local_coords = false
	_legacy_fx.visibility_aabb = AABB(
		Vector3(-4.0, -0.5, -4.0), Vector3(8.0, 3.0, 8.0))
	_legacy_proc = ParticleProcessMaterial.new()
	_legacy_proc.direction = (Vector3.UP * 0.55 - _run_dir).normalized()
	_legacy_proc.spread = LEGACY_SPREAD
	_legacy_proc.initial_velocity_min = LEGACY_SPEED * 0.4
	_legacy_proc.initial_velocity_max = LEGACY_SPEED
	_legacy_proc.gravity = Vector3(0.0, -9.0, 0.0)
	_legacy_proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_legacy_proc.emission_box_extents = Vector3(0.12, 0.03, 0.12)
	_legacy_proc.scale_min = 0.6
	_legacy_proc.scale_max = 1.3
	_legacy_fx.process_material = _legacy_proc
	match kind:
		ForestGround.Surface.STONE:
			_legacy_fx.draw_passes = 1
			_legacy_fx.draw_pass_1 = _legacy_quad(_legacy_stone_tex, 1.0)
		ForestGround.Surface.GRASS:
			_legacy_fx.draw_passes = 2
			_legacy_fx.draw_pass_1 = _legacy_quad(LEGACY_DIRT_TEX, 1.0)
			_legacy_fx.draw_pass_2 = _legacy_quad(LEGACY_GRASS_TEX, 0.7)
		_:
			_legacy_fx.draw_passes = 1
			_legacy_fx.draw_pass_1 = _legacy_quad(LEGACY_DIRT_TEX, 1.0)
	_legacy_fx.emitting = false
	_world.add_child(_legacy_fx)


## Кадр «было»: эмиссия и доля — как в старом update() (кривая по скорости,
## бег ~1.0 → полные 26 частиц непрерывно).
func _update_legacy() -> void:
	if _legacy_fx == null:
		return
	var body := _player as CharacterBody3D
	if body == null:
		return
	var hspeed: float = Vector2(body.velocity.x, body.velocity.z).length()
	var t: float = (hspeed - B.anim_idle_speed) / (B.run_speed - B.anim_idle_speed)
	_legacy_fx.emitting = body.is_on_floor() and hspeed > B.anim_idle_speed
	_legacy_fx.amount_ratio = pow(clampf(t, 0.0, 1.0), 1.6)
	_legacy_fx.global_position = _player.global_position + Vector3(0.0, 0.05, 0.0)


## Квад «было» — дословно старый _quad(): альфа 0.9, биллборд, без света.
func _legacy_quad(tex: Texture2D, scale: float) -> QuadMesh:
	var quad := QuadMesh.new()
	var side: float = LEGACY_SIZE * scale
	quad.size = Vector2(side, side)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = Color(1.0, 1.0, 1.0, LEGACY_ALPHA)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = mat
	return quad


## Синхронный снимок: ровно один рендер текущего состояния, затем PNG.
func _force_shot(name: String) -> void:
	RenderingServer.force_draw(true, 0.0)
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("%s/%s.png" % [_out, name])
