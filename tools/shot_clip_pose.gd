# Визуальная самопроверка поз клипов (П5.8, попытка 2, дефект рук): снимает
# персонажа в заданном кадре клипа с трёх ракурсов в builds/shots_pose/.
# Это инструмент самопроверки агента, материалы для владельца не снимаются.
#   xvfb-run -a godot --path . --resolution 1280x720 --rendering-driver opengl3 \
#     res://tools/shot_clip_pose.tscn -- --clip=Wave_Hand --t=0.6
# (t можно несколько: --t=0.6,1.25 ; ракурс --view=front,side,diag,all)
extends Node3D

const MODEL: PackedScene = preload("res://gameplay/player/character_model.tscn")
const OUT_DIR: String = "builds/shots_pose"
const MAX_FRAMES: int = 900


func _ready() -> void:
	var clip_name := "Wave_Hand"
	var times: Array[float] = [0.6]
	var view := "all"
	var gender := 0
	var dist := 1.0
	var look_y := 1.45
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--clip="):
			clip_name = a.substr(7)
		elif a.begins_with("--t="):
			times = []
			for part: String in a.substr(4).split(","):
				times.append(part.to_float())
		elif a.begins_with("--view="):
			view = a.substr(7)
		elif a.begins_with("--gender="):
			gender = int(a.substr(9))
		elif a.begins_with("--dist="):
			dist = a.substr(7).to_float()
		elif a.begins_with("--looky="):
			look_y = a.substr(8).to_float()
	DirAccess.make_dir_recursive_absolute("res://" + OUT_DIR)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.17, 0.17, 0.20)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.66, 0.66, 0.7)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, -30.0, 0.0)
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(10.0, 10.0)
	ground.mesh = plane
	add_child(ground)

	var model := MODEL.instantiate() as CharacterModel
	add_child(model)
	model.setup_appearance(Appearance.default_for(gender))
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true

	for i: int in 10:
		await get_tree().process_frame
	var view_list: PackedStringArray = [view] if view != "all" else \
		PackedStringArray(["front", "side", "diag", "back"])
	var views: Array = []
	for v: String in view_list:
		match v:
			"front":
				views.append(["front", Vector3(0.0, 1.05, 3.2)])
			"side":
				views.append(["side", Vector3(3.2, 1.05, 0.0)])
			"diag":
				views.append(["diag", Vector3(2.3, 1.05, 2.3)])
			"back":
				views.append(["back", Vector3(0.0, 1.05, -3.2)])
	for v in views:
		camera.global_position = Vector3(0.0, look_y, 0.0) \
			+ (v[1] as Vector3).normalized() * 3.2 * dist
		camera.look_at(Vector3(0.0, look_y, 0.0))
		for t: float in times:
			_reach(model, clip_name, t)
			var fname := "%s/%s_g%d_t%05.2f_%s.png" % [OUT_DIR, clip_name,
				gender, t, v[0]]
			# Текстура вьюпорта готова не сразу — прогреть кадры (диаг-стенд
			# ждёт 0.15 с, иначе снимок чёрный).
			await get_tree().create_timer(0.15).timeout
			get_viewport().get_texture().get_image().save_png(fname)
			print("снято: %s" % fname)
			model.set_state(Protocol.AnimState.IDLE)
			await get_tree().physics_frame
	get_tree().quit(0)


## Дождаться позиции клипа (кадры физики — advance() не применяет бленд).
func _reach(model: CharacterModel, clip_name: String, target: float) -> void:
	model._player.speed_scale = 1.0
	model._player.play("%s/%s" % [CharacterAnims.LIB_NAME, clip_name], 0.0)
	for i: int in MAX_FRAMES:
		if model._player.get_current_animation_position() >= target:
			return
		await get_tree().physics_frame
