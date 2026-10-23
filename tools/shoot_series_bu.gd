extends SceneTree
## Серия кадров П10: вход в мир настоящим путём (boot → меню BU → старт →
## LoadingScreenBU → мир) под xvfb/opengl3. Каждый кадр после первых десяти
## аудитится на «серый/пустой» (плоский немалый по яркости цвет) — критерий
## SPEC П10 4.3 «ни одного серого кадра между затуханием меню и миром»;
## ключевые кадры перехода и игровые ракурсы героя сохраняются в PNG.
## Запуск: xvfb-run -a godot --path . --rendering-driver opengl3 \
##   --resolution 1280x720 -s res://tools/shoot_series_bu.gd -- <папка png>
## Выход: 0 — серия снята и серых кадров нет; 2 — снята, но есть серые;
## 3 — мир не достигнут.

const SHOT_DIR_ARG: int = 0
## Первые кадры — сплэш движка/очистка окна: в аудит не идут.
const AUDIT_FROM_FRAME: int = 10
## Ключевые кадры перехода — каждый N-й (остальные только статистика).
const PNG_EVERY: int = 25
## Порог «плоского» кадра: разброс каналов по выборке меньше этого.
const FLAT_SPREAD: float = 0.02
## Плоский кадр темнее этого — законное затухание меню (в чёрный), не дефект.
const BLACK_LUMA: float = 0.06
const WORLD_TIMEOUT_S: float = 200.0

var _out: String = ""
var _frame: int = 0
var _t: float = 0.0
var _flat: PackedStringArray = PackedStringArray()
var _world: Node3D = null
var _world_at: float = -1.0
var _world_seen: bool = false
var _settle: float = 0.0
## 0 — идёт вход, 1 — покой, 2 — бег, 3 — прыжок, 4 — меч, 5 — площадь,
## 6 — лицо, 7 — готово.
var _stage: int = 0
var _stage_t: float = 0.0
var _temp_cam: Camera3D = null
var _player_cam: Camera3D = null


func _initialize() -> void:
	_out = OS.get_cmdline_user_args()[SHOT_DIR_ARG]
	DirAccess.make_dir_recursive_absolute(_out)
	# Автовход, как у бота: меню BU само нажмёт «Новая игра» через секунду.
	var session: Node = root.get_node_or_null("/root/Session")
	if session != null:
		session.set("bot", true)
	root.add_child((load("res://scenes/boot.tscn") as PackedScene).instantiate())
	print("SERIES: старт, кадры в %s" % _out)


func _process(delta: float) -> bool:
	_frame += 1
	_t += delta
	if _frame >= AUDIT_FROM_FRAME:
		_audit_frame()
	if _frame % PNG_EVERY == 0:
		_shot("series_%04d_f%.1f" % [_frame, _t])
	if _world == null:
		var found: Node = root.find_child("WorldScene", true, false)
		if found != null:
			_world = found as Node3D
			_world_at = _t
			_world_seen = true
			# Дальше бот не нужен: ракурсы снимаем сами, ходьба бота мешала бы.
			var session: Node = root.get_node_or_null("/root/Session")
			if session != null:
				session.set("bot", false)
			print("SERIES: мир в кадре %.1f с" % _t)
		elif _t > WORLD_TIMEOUT_S:
			print("SERIES FAIL: мир не достигнут за %.0f с" % _t)
			quit(3)
			return true
		return false
	if LoadingScreenBU.current != null:
		return false  # экран загрузки ещё держит кадр
	if _world_at > 0.0 and _stage == 0:
		_settle += delta
		if _settle >= 2.0:
			_next_stage(1)
			return false
	_stage_t += delta
	match _stage:
		1:
			if _stage_t >= 1.0:
				_shot("20_world_idle")
				_next_stage(2)
		2:
			if _stage_t < 0.05:
				Input.action_press("move_forward")
			elif _stage_t >= 1.2 and not _stage_t >= 1.35:
				_shot("21_world_run")
			elif _stage_t >= 1.5:
				Input.action_release("move_forward")
				_next_stage(3)
		3:
			if _stage_t < 0.05:
				Input.action_press("jump")
			elif _stage_t >= 0.12:
				Input.action_release("jump")
			if _stage_t >= 0.5 and _stage_t < 0.65:
				_shot("22_world_jump")
			elif _stage_t >= 2.2:
				_next_stage(4)
		4:
			if _stage_t < 0.05:
				var hero := _hero()
				if hero != null:
					hero.equip.select(&"sword")
			if _stage_t >= 1.6:
				_shot("23_world_sword")
				_next_stage(5)
		5:
			if _stage_t < 0.05:
				_plaza_camera()
			if _stage_t >= 0.8:
				_shot("24_world_plaza")
				_restore_camera()
				_next_stage(6)
		6:
			if _stage_t < 0.05:
				_face_camera()
			elif absf(_stage_t - 0.9) < 0.03:
				var blink: Node = _blink()
				if blink != null:
					blink.call("blink")
			if _stage_t >= 0.98 and _stage_t < 1.12:
				_shot("25_world_face_blink")
			elif _stage_t >= 2.0 and _stage_t < 2.15:
				_shot("26_world_face")
			elif _stage_t >= 2.3:
				_restore_camera()
				_next_stage(7)
		7:
			print("SERIES: кадров %d, плоских не-чёрных: %d" % [_frame, _flat.size()])
			if _flat.size() > 0:
				for line: String in _flat:
					print("SERIES GRAY: %s" % line)
				print("SERIES FAIL: есть серые/пустые кадры")
				quit(2)
			else:
				print("SERIES PASS: серых кадров нет")
				quit(0)
			return true
	return false


# --- Аудит кадра и съёмка ---

func _audit_frame() -> void:
	var img: Image = root.get_texture().get_image()
	if img == null:
		return
	var w: int = img.get_width()
	var h: int = img.get_height()
	if w <= 0 or h <= 0:
		return
	var c0: Color = img.get_pixel(w / 2, h / 2)
	var lo: Color = c0
	var hi: Color = c0
	var step: int = maxi(w / 32, 1)
	for y: int in range(8, h, maxi(h / 18, 1)):
		for x: int in range(8, w, step):
			var c: Color = img.get_pixel(x, y)
			lo = Color(minf(lo.r, c.r), minf(lo.g, c.g), minf(lo.b, c.b))
			hi = Color(maxf(hi.r, c.r), maxf(hi.g, c.g), maxf(hi.b, c.b))
	var spread: float = maxf(maxf(hi.r - lo.r, hi.g - lo.g), hi.b - lo.b)
	if spread < FLAT_SPREAD:
		var luma: float = c0.get_luminance()
		if luma > BLACK_LUMA:
			_flat.append("кадр %d (%.2f с), цвет #%s" % [
				_frame, _t, c0.to_html(false)])


func _shot(name: String) -> void:
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("%s/%s.png" % [_out, name])


# --- Ракурсы ---

func _next_stage(next: int) -> void:
	_stage = next
	_stage_t = 0.0


func _player() -> Node3D:
	return _world.get_node_or_null("Player") as Node3D


func _hero() -> HeroModelBU:
	var p: Node3D = _player()
	if p == null:
		return null
	return p.get_node_or_null("Model/Visual") as HeroModelBU


func _blink() -> Node:
	var hero: HeroModelBU = _hero()
	if hero == null:
		return null
	var lids: Array[Node] = hero.find_children("*", "BlinkLidsBU", true, false)
	return lids[0] if lids.size() > 0 else null


func _swap_camera(pos: Vector3, at: Vector3, fov: float) -> void:
	var p: Node3D = _player()
	if p == null:
		return
	_temp_cam = Camera3D.new()
	_world.add_child(_temp_cam)
	_temp_cam.fov = fov
	_temp_cam.look_at_from_position(pos, at)
	_temp_cam.make_current()


func _restore_camera() -> void:
	if _temp_cam != null:
		_temp_cam.queue_free()
		_temp_cam = null
	if _player_cam != null:
		_player_cam.make_current()


func _plaza_camera() -> void:
	var p: Node3D = _player()
	if p == null:
		return
	_player_cam = _world.get_viewport().get_camera_3d()
	var center: Vector3 = p.global_position
	_swap_camera(center + Vector3(0.0, 14.0, 16.0), center, 55.0)


func _face_camera() -> void:
	var p: Node3D = _player()
	if p == null:
		return
	_player_cam = _world.get_viewport().get_camera_3d()
	var head: Vector3 = p.global_position + Vector3(0.0, 1.62, 0.0)
	var fwd: Vector3 = -p.global_transform.basis.z
	_swap_camera(head + fwd * 1.05 + Vector3(0.12, 0.03, 0.0), head, 30.0)
