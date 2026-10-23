extends SceneTree
## Серия кадров П10: вход в мир настоящим путём (boot → меню BU → старт →
## LoadingScreenBU → мир) под xvfb/opengl3. Каждый кадр после первых десяти
## аудитится на «серый/пустой» (плоский немалый по яркости цвет) — критерий
## SPEC П10 4.3 «ни одного серого кадра между затуханием меню и миром»;
## ключевые кадры перехода и игровые ракурсы героя сохраняются в PNG.
## Запуск: xvfb-run -a godot --path . --rendering-driver opengl3 \
##   --resolution 1280x720 -s res://tools/shoot_series_bu.gd -- --bot <папка png>
## Выход: 0 — серия снята и серых кадров нет; 2 — снята, но есть серые;
## 3 — мир не достигнут.
##
## Кадр мира под llvmpipe стоит 6-20 с (замер: остров на Площади, 720p и
## 360p, с get_image() и без — одинаково), поэтому стадии считаются кадрами,
## а не секундами: дельта кадра больше любых временных окон. get_image()
## возвращает ЗАВЕРШЁВШИЙСЯ кадр, поэтому действие делается за 2-3 кадра
## до снимка. Моргание ловится замедлением Engine.time_scale: веки BinkLidsBU
## закрываются на 0.08 с и при полной скорости пролетают за один кадр.
##
## Лаг рендера под llvmpipe (замер tools/diag_series_cam.gd): viewport
## переключается на временную камеру сразу, но get_image() и через 2 кадра
## возвращает пиксели, отрисованные ДО make_current() — при кадрах в
## десятки секунд RenderingServer отстаёт на 2-3 кадра. Поэтому после
## смены ракурса (стадии 5-6) до снимка держится выдержка в 4-5 кадров,
## а не 2-3.

## Первые кадры — сплэш движка/очистка окна: в аудит не идут.
const AUDIT_FROM_FRAME: int = 10
## Каждый N-й кадр — PNG серии (меню дешёвое, мир редкий).
const PNG_EVERY: int = 8
## Порог «плоского» кадра: разброс каналов по выборке меньше этого.
const FLAT_SPREAD: float = 0.02
## Плоский кадр темнее этого — законное затухание меню (в чёрный), не дефект.
const BLACK_LUMA: float = 0.06
const WORLD_TIMEOUT_S: float = 200.0
## Замедление на стадии моргания. SkeletonModifier3D получает ФИЗИЧЕСКИЕ
## дельты (проба builds/probe_blink_delta.gd: 3 вызова, сумма 0.128 с при
## кадре в 1 с — это 8 шагов физики по 1/60, а не дельта кадра), поэтому
## за тяжёлый кадр веки проходят ровно 8/60 × time_scale: при 0.3 второй
## кадр моргания попадает в максимум sin(k·π) (k=0.5, глаза закрыты).
const BLINK_TIME_SCALE: float = 0.3

var _out: String = ""
## --from-stage=N: после входа в мир сразу перейти к стадии N (пересъём
## ракурсов 5-6 без повторения покоя/бега/прыжка/меча).
var _from_stage: int = 0
var _frame: int = 0
var _t: float = 0.0
var _flat: PackedStringArray = PackedStringArray()
var _world: Node3D = null
var _loading_seen: bool = false
## 0 — идёт вход, 1 — покой, 2 — бег, 3 — прыжок, 4 — меч, 5 — площадь,
## 6 — лицо, 7 — готово.
var _stage: int = 0
var _stage_frame: int = 0
var _temp_cam: Camera3D = null
var _player_cam: Camera3D = null


func _initialize() -> void:
	# Первый не-флаговый аргумент — каталог PNG (флаги типа --bot идут
	# в тот же список юзер-аргов и здесь игнорируются).
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			_out = arg
		elif arg.begins_with("--from-stage="):
			_from_stage = int(arg.substr("--from-stage=".length()))
	if _out.is_empty():
		push_error("SERIES FAIL: не задан каталог для PNG (аргумент после --)")
		quit(3)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	# Автовход — аргументом --bot (Dev → Session): без него boot без Steam
	# останавливается на окне «Steam не запущен» и в мир не входит.
	# Обращаться к автолоаду из _initialize нельзя (дерево ещё не активно).
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
		if not _loading_seen and LoadingScreenBU.current != null:
			_loading_seen = true
			_shot("11_loading_first")
		var found: Node = root.find_child("WorldScene", true, false)
		if found != null:
			_world = found as Node3D
			_shot("12_world_added")
			# Дальше бот не нужен: ракурсы снимаем сами, ходьба бота мешала бы.
			# Ходок BotController создаётся в player._ready при Session.bot —
			# к нашему кадру он уже жив и флаг не перечитывает, освобождаем.
			# (Автолоады в -s-туле не видны компилятору — ищем узлом в _process.)
			var p: Node3D = found.get_node_or_null("Player")
			if p != null:
				for bot: Node in p.find_children("*", "BotController", true, false):
					bot.queue_free()
			var session: Node = root.get_node_or_null("Session")
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
	if _stage == 0:
		if _loading_seen:
			_shot("13_world_revealed")
		_next_stage(maxi(_from_stage, 1))
		return false
	_stage_frame += 1
	match _stage:
		1:
			# покой: пара кадров на успокоение мира после ухода экрана
			if _stage_frame == 3:
				_shot("20_world_idle")
				_next_stage(2)
		2:
			# бег: разгон за три кадра (по 8 физических шагов на кадр)
			if _stage_frame == 1:
				Input.action_press("move_forward")
			elif _stage_frame == 4:
				_shot("21_world_run")
			elif _stage_frame == 5:
				Input.action_release("move_forward")
				_next_stage(3)
		3:
			if _stage_frame == 1:
				Input.action_press("jump")
			elif _stage_frame == 2:
				Input.action_release("jump")
			elif _stage_frame == 3:
				_shot("22_world_jump")
			elif _stage_frame == 5:
				_next_stage(4)
		4:
			# меч: выхват и стойка — твину и анимации хватит одного кадра,
			# снимаем через четыре
			if _stage_frame == 1:
				var hero: HeroModelBU = _hero()
				if hero != null:
					hero.equip.select(&"sword")
			elif _stage_frame == 5:
				_shot("23_world_sword")
			elif _stage_frame == 6:
				_next_stage(5)
		5:
			# Площадь с высоты: вид без костра и жителей. Выдержка 5 кадров:
			# рендер отстаёт от make_current() на 2-3 кадра (см. шапку).
			if _stage_frame == 1:
				_plaza_camera()
			elif _stage_frame == 6:
				_shot("24_world_plaza")
			elif _stage_frame == 7:
				_restore_camera()
				_next_stage(6)
		6:
			# лицо крупно; на втором кадре — моргание под замедленным временем.
			# Кадр моргания снимается через 2 кадра после blink(): при 0.3
			# веки в максимуме на 2-3 кадре, а отстающий рендер возвращает
			# именно их. Финальный кадр — через 4 кадра после возврата
			# скорости: глаза открыты, камера лица уже точно в пикселях.
			if _stage_frame == 1:
				_face_camera()
			elif _stage_frame == 2:
				Engine.time_scale = BLINK_TIME_SCALE
				var blink: Node = _blink()
				if blink != null:
					blink.call("blink")
			elif _stage_frame == 4:
				_shot("25_world_face_blink")
			elif _stage_frame == 5:
				Engine.time_scale = 1.0
			elif _stage_frame == 9:
				_shot("26_world_face")
			elif _stage_frame == 10:
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
	_stage_frame = 0


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
