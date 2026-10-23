extends SceneTree
## Разовая диагностика П10: почему shoot_series_bu.gd не переключает камеру
## на ракурсах площади/лица. Входит в мир тем же путём (--bot), печатает
## дерево игрока, пробует make_current() и через 2 кадра — какая камера
## текущая и откуда смотрит. Снимает 2 кадра: до и после.
## Запуск: xvfb-run -a godot --path . --rendering-driver opengl3 \
##   --resolution 1280x720 -s res://tools/diag_series_cam.gd -- --bot <папка>

var _out: String = ""
var _frame: int = 0
var _t: float = 0.0
var _world: Node3D = null
var _phase: int = 0


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			_out = arg
	root.add_child((load("res://scenes/boot.tscn") as PackedScene).instantiate())
	print("DIAG: старт")


func _process(delta: float) -> bool:
	_frame += 1
	_t += delta
	if _world == null:
		var found: Node = root.find_child("WorldScene", true, false)
		if found != null:
			_world = found as Node3D
			var p: Node3D = found.get_node_or_null("Player") as Node3D
			print("DIAG: мир %.1f с, Player=%s" % [_t, p.name if p != null else "<нет>"])
			if p != null:
				_dump_player(p)
		elif _t > 200.0:
			print("DIAG FAIL: мир не достигнут")
			quit(3)
			return true
		return false
	if LoadingScreenBU.current != null:
		return false
	_phase += 1
	var p: Node3D = _world.get_node_or_null("Player") as Node3D
	var cam_now: Camera3D = _world.get_viewport().get_camera_3d()
	match _phase:
		1:
			print("DIAG: фаза 1, камера сейчас: %s pos=%s fov=%.1f current=%s" % [
				cam_now.name if cam_now != null else "<нет>",
				cam_now.global_position if cam_now != null else Vector3.ZERO,
				cam_now.fov if cam_now != null else -1.0,
				cam_now.is_current() if cam_now != null else false])
			_shot("90_diag_before")
			# v3: не переключаем current (рендер его игнорирует под
			# opengl3/llvmpipe), а перемещаем САМУ камеру игрока:
			# top_level отцепляет её от CameraRig/SpringArm.
			if cam_now != null and p != null:
				cam_now.top_level = true
				cam_now.fov = 55.0
				cam_now.look_at_from_position(
					p.global_position + Vector3(0.0, 14.0, 16.0),
					p.global_position)
				print("DIAG: камера игрока top_level + перенос на высоту")
		2:
			RenderingServer.force_draw(true, 0.0)
			_shot("92_diag_force1")
			print("DIAG: force_draw №1 + снимок")
		3:
			RenderingServer.force_draw(true, 0.0)
			_shot("93_diag_force2")
			print("DIAG: force_draw №2 + снимок")
		4:
			print("DIAG: конец")
			quit(0)
			return true
	return false


func _dump_player(p: Node3D) -> void:
	for child: Node in p.get_children():
		print("DIAG: Player/%s (%s)" % [child.name, child.get_class()])
	var model: Node = p.get_node_or_null("Model")
	if model != null:
		for child: Node in model.get_children():
			print("DIAG: Player/Model/%s (%s)" % [child.name, child.get_class()])
	var visual: Node = p.get_node_or_null("Model/Visual")
	print("DIAG: Model/Visual=%s (%s)" % [
		visual.name if visual != null else "<нет>",
		visual.get_script() if visual != null else ""])


func _shot(name: String) -> void:
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("%s/%s.png" % [_out, name])
		print("DIAG: снят %s" % name)
