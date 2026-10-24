extends SceneTree
## Съёмка частиц шагов FootFx (переделка П9 по замечанию владельца) под
## xvfb/llvmpipe: игрок настоящим путём входит в мир (--bot), затем по
## найденным на запечённом острове отрезкам травы/грязи/земли/камня идёт
## и бежит, кадры пишутся серией. Замедление Engine.time_scale: кадр
## llvmpipe стоит 6-20 с, симуляции за кадр должно проходить ~0.15 с —
## тогда порция (жизнь 0.55 с) живёт 2-4 кадра и попадает в кадр в
## полёте, а не умирает между кадрами. В имени кадра — «возраст» последней
## порции: b0 — порция в этом кадре, b1/b2 — кадр-два спустя, b3 — давно.
## Сырая серия — в builds/screenshots/footfx_raw (не в git); отобранные
## кадры и склейки кладутся в docs/screenshots/footfx после просмотра.
## Запуск:
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 -s res://tools/shoot_footfx.gd -- --bot <каталог>
## Выход: 0 — все сцены сняты; 3 — мир не достигнут; 4 — не задан каталог.

const ART: IslandArt = preload("res://gameplay/world/island_art.res")

## Симуляция за кадр рендера: 6-20 с × 0.02 = 0.12-0.4 с (физика вдобавок
## ограничена 8 тиками = 0.133 с на кадр — детект шагов по костям это
## переживает: порции всё равно попадают в кадры).
const TIME_SCALE: float = 0.02
## Кадров на сцену: пара на разгон + ~2 цикла локомоции.
const FRAMES_PER_SCENE: int = 8
## Проверяемая длина пробега, м: кадр ~0.7 м, 8 кадров + разбег.
const SEGMENT_M: float = 12.0
## Минимальная высота земли отрезка: ниже — море/мелководье/лужа у воды.
const MIN_H: float = 0.45
## Максимальный уклон пробега (тангенс): круче — не пробег, а скольжение.
const MAX_SLOPE: float = 0.35
## Радиус вокруг Площади, где отрезки не ищем: там своё покрытие — гравий.
const PLAZA_AVOID: float = 32.0

var _out: String = ""
var _t: float = 0.0
var _world: Node3D = null
var _loading_seen: bool = false
var _player: Node3D = null
var _foot_fx: FootFx = null
## Сцены: name, seg, walk, cam ("game"/"feet"), jump.
var _scenes: Array[Dictionary] = []
var _segments: Dictionary = {}
var _scene_i: int = -1
var _frame_in_scene: int = 0
var _run_dir := Vector3(1.0, 0.0, 0.0)
var _feet_cam: Camera3D = null
var _base_steps: int = 0
var _seen_bursts: int = 0
var _frames_since_burst: int = 99


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			_out = arg
	if _out.is_empty():
		push_error("FOOTFX FAIL: не задан каталог PNG (аргумент после --)")
		quit(4)
		return
	DirAccess.make_dir_recursive_absolute(_out)
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
			var p: Node3D = found.get_node_or_null("Player")
			if p != null:
				for bot: Node in p.find_children("*", "BotController", true, false):
					bot.queue_free()
				_player = p
				_foot_fx = p.get_node_or_null("FootFx") as FootFx
			var session: Node = root.get_node_or_null("Session")
			if session != null:
				session.set("bot", false)
			print("FOOTFX: мир в кадре %.1f с" % _t)
		elif _t > 240.0:
			print("FOOTFX FAIL: мир не достигнут")
			quit(3)
			return true
		return false
	if LoadingScreenBU.current != null:
		return false  # экран загрузки ещё держит кадр
	if _scene_i < 0:
		_setup_scenes()
		return false
	return _run_scene()


## Сценарии: ходьба/бег × камера игры/крупно у ног по покрытиям с частицами
## (трава, грязь, лужа, земля); камню достаточно бега (отрицательный случай
## — частиц быть не должно); прыжок-приземление и лента подряд идущих
## кадров для склейки-«клипа».
func _setup_scenes() -> void:
	Engine.time_scale = TIME_SCALE
	_segments["dirt"] = _plaza_segment()
	for key: String in ["grass", "mud", "puddle", "stone"]:
		_segments[key] = _find_segment(_kind_of(key))
		if _segments[key].is_empty():
			print("FOOTFX: отрезок %s не найден — сцены пропущены" % key)
	for key: String in ["grass", "mud", "puddle", "dirt"]:
		if _segments[key].is_empty():
			continue
		for speed: String in ["walk", "run"]:
			for cam: String in ["game", "feet"]:
				_scenes.append({"name": "%s_%s_%s" % [speed, key, cam],
					"seg": key, "walk": speed == "walk",
					"cam": cam, "jump": false})
	if not _segments["stone"].is_empty():
		for cam: String in ["game", "feet"]:
			_scenes.append({"name": "run_stone_%s" % cam, "seg": "stone",
				"walk": false, "cam": cam, "jump": false})
	if not _segments["dirt"].is_empty():
		_scenes.append({"name": "jump_dirt_feet", "seg": "dirt",
			"walk": false, "cam": "feet", "jump": true})
	if not _segments["mud"].is_empty():
		_scenes.append({"name": "strip_mud_feet", "seg": "mud",
			"walk": false, "cam": "feet", "jump": false})
	_next_scene()
	print("FOOTFX: сцен %d" % _scenes.size())


func _kind_of(key: String) -> int:
	match key:
		"grass": return ForestGround.Surface.GRASS
		"mud": return ForestGround.Surface.MUD
		"puddle": return ForestGround.Surface.PUDDLE
		"stone": return ForestGround.Surface.STONE
	return ForestGround.Surface.DIRT


## Один кадр текущей сцены: следящая камера у ног, маркер «возраста»
## последней порции, снимок.
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
	if scene["cam"] == "feet":
		_update_feet_cam()
	if scene["jump"] and _frame_in_scene == 3:
		Input.action_press("jump")
	elif scene["jump"] and _frame_in_scene == 4:
		Input.action_release("jump")
	_shot("%s_f%02d_b%d" % [scene["name"], _frame_in_scene,
		mini(_frames_since_burst, 3)])
	if _frame_in_scene >= FRAMES_PER_SCENE:
		print("FOOTFX: %s — шагов %d, порций %d" % [scene["name"],
			_foot_fx.stats_steps - _base_steps,
			_foot_fx.stats_bursts - _scene_burst_base])
		_next_scene()
	return false


var _scene_burst_base: int = 0


func _next_scene() -> void:
	Input.action_release("move_forward")
	Input.action_release("walk")
	Input.action_release("jump")
	if _feet_cam != null:
		_feet_cam.queue_free()
		_feet_cam = null
	_scene_i += 1
	_frame_in_scene = 0
	_frames_since_burst = 99
	if _scene_i >= _scenes.size():
		print("FOOTFX PASS: снято сцен %d" % _scenes.size())
		quit(0)
		return
	if _foot_fx != null:
		_base_steps = _foot_fx.stats_steps
		_scene_burst_base = _foot_fx.stats_bursts
		_seen_bursts = _foot_fx.stats_bursts


## Поставить игрока в начало отрезка, развернуть камеру игрока по
## направлению пробега, зажать ход; сцене «у ног» — следящая камера.
func _teleport(scene: Dictionary) -> void:
	var seg: Dictionary = _segments[scene["seg"]]
	var start: Vector3 = seg["start"]
	_run_dir = seg["dir"]
	_player.velocity = Vector3.ZERO
	_player.global_position = start
	var rig: Node3D = _player.get_node_or_null("CameraRig")
	if rig != null:
		rig.rotation.y = atan2(-_run_dir.x, -_run_dir.z)
	if scene["cam"] == "feet":
		_feet_cam = Camera3D.new()
		_feet_cam.fov = 55.0
		_world.add_child(_feet_cam)
		_update_feet_cam()
		_feet_cam.make_current()
	Input.action_press("move_forward")
	if scene["walk"]:
		Input.action_press("walk")


## Камера у ног: полметра над землёй, сбоку-спереди от бегущего; каждый
## кадр следует за игроком (рендер и отстаёт на 2-3 кадра, но в отставшем
## кадре камера и игрок согласованы — стопы в кадре).
func _update_feet_cam() -> void:
	if _feet_cam == null:
		return
	var feet: Vector3 = _player.global_position
	var side := Vector3(-_run_dir.z, 0.0, _run_dir.x)
	var pos := feet + _run_dir * 1.4 + side * 1.0
	pos.y = maxf(feet.y + 0.55,
		IslandGen.ground_height(ART.heights, pos.x, pos.z) + 0.35)
	_feet_cam.global_position = pos
	_feet_cam.look_at(feet + _run_dir * 0.4 + Vector3(0.0, 0.25, 0.0))


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


func _shot(name: String) -> void:
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("%s/%s.png" % [_out, name])
