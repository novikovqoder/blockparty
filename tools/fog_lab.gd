# Лаборатория тумана (диагностика шага 1 П4.5): плоскость с обычным
# StandardMaterial3D (без нашего шейдера), куб для масштаба и камера
# с высоты глаз. Один снимок PNG — быстрые A/B-прогоны настроек тумана
# без загрузки острова. Запуск (виртуальный экран + software-рендер):
#   xvfb-run -a godot --path . -s tools/fog_lab.gd \
#     --resolution 640x360 --rendering-driver opengl3 \
#     -- --fog=1 --density=0.0025 --out=/tmp/fog.png
# Параметры (после --): fog=0|1, density=Ч, height_density=Ч, height=Ч,
# out=ПУТЬ (по умолчанию /tmp/fog_lab.png), shader=standard|lowpoly,
# sun=Ч (энергия солнца), ambient=Ч (энергия ambient), albedo=HEX.
extends SceneTree


func _initialize() -> void:
	var params := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var kv: PackedStringArray = arg.substr(2).split("=", true, 2)
			params[kv[0]] = kv[1] if kv.size() > 1 else "1"

	var root := Node3D.new()
	root.name = "FogLab"
	# Снимаем через SubViewport: у корневого окна в SceneTree-скрипте камера
	# активируется ненадёжно (позиция, заданная до первого кадра, терялась,
	# снимок выходил из начала координат) — SubViewport рендерит управляемо.
	var view := SubViewport.new()
	view.size = Vector2i(640, 360)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(view)
	view.add_child(root)

	var sun := DirectionalLight3D.new()
	sun.light_energy = params.get("sun", "0.9").to_float()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	root.add_child(sun)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.44, 0.64, 0.85)
	sky_mat.sky_horizon_color = Color(0.74, 0.83, 0.9)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.66, 0.74, 0.82)
	env.ambient_light_energy = params.get("ambient", "0.52").to_float()
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.fog_light_color = Color(0.74, 0.83, 0.9)
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)
	# Тёмный фон для terrain-теста: белая геометрия не должна сливаться с небом.
	if params.get("bg", "sky") == "dark":
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.05, 0.05, 0.08)

	# Земля — насыщенная травяная зелень: сразу видно, сколько пелены сверху.
	# terrain=1 — вместо плоскости первый чанк реального острова (диагностика
	# шага 2 П4.5: рельеф в мировом рендере выходил равномерно белым).
	var albedo := Color.from_string(params.get("albedo", "388c4d"), Color(0.2, 0.55, 0.3))
	var plane := MeshInstance3D.new()
	var terrain_center := Vector3(0.0, 0.8, -10.0)
	if params.get("terrain", "0") == "1":
		var island: Node = (load("res://gameplay/world/island.tscn") as PackedScene).instantiate()
		root.add_child(island)
		await process_frame
		# Море и озеро мешают разглядеть сам чанк — прячем до снимка.
		for water in island.find_children("*", "WaterArea"):
			(water as Node).visible = false
		var chunk: MeshInstance3D = null
		var max_h := -9999.0
		var min_h := 9999.0
		var thick := 0.0
		for child in (island.get_node("IslandView/Terrain") as Node).get_children():
			var mi := child as MeshInstance3D
			if mi == null:
				continue
			var b: AABB = (mi.mesh as ArrayMesh).get_aabb()
			max_h = maxf(max_h, b.position.y + b.size.y)
			min_h = minf(min_h, b.position.y)
			thick = maxf(thick, b.size.y)
			if chunk == null or b.size.y > (chunk.mesh as ArrayMesh).get_aabb().size.y:
				chunk = mi
		print("рельеф: min_y=%.2f max_y=%.2f макс_толщина=%.2f" % [min_h, max_h, thick])
		var aabb: AABB = (chunk.mesh as ArrayMesh).get_aabb()
		print("чанк: pos=%s aabb=%s материал=%s" % [chunk.global_position, aabb, chunk.material_override])
		plane.mesh = chunk.mesh
		plane.material_override = chunk.material_override
		terrain_center = chunk.global_position + aabb.get_center()
		island.queue_free()
	else:
		var plane_mesh := PlaneMesh.new()
		plane_mesh.size = Vector2(40.0, 40.0)
		plane.mesh = plane_mesh
		if params.get("shader", "standard") == "lowpoly":
			var lowpoly := ShaderMaterial.new()
			lowpoly.shader = preload("res://assets/shaders/lowpoly.gdshader")
			lowpoly.set_shader_parameter("albedo", albedo)
			plane.material_override = lowpoly
		else:
			var ground := StandardMaterial3D.new()
			ground.albedo_color = albedo
			plane.material_override = ground
	root.add_child(plane)

	var box := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(1.0, 1.0, 1.0)
	box.mesh = box_mesh
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.8, 0.3, 0.2)
	box.material_override = red
	box.position = Vector3(0.0, 0.5, -6.0)
	root.add_child(box)

	var camera := Camera3D.new()
	root.add_child(camera)

	if params.get("fog", "1") == "1":
		env.fog_enabled = true
		env.fog_density = params.get("density", "0.0025").to_float()
		env.fog_height_density = params.get("height_density", "0.0").to_float()
		env.fog_height = params.get("height", "0.0").to_float()

	if params.get("terrain", "0") == "1":
		# Сверху на центр самого рельефного чанка (мировые координаты меша).
		camera.position = terrain_center + Vector3(18.0, 30.0, 18.0)
		camera.look_at(terrain_center)
	elif params.get("top", "0") == "1":
		# Порядок важен: rotation_degrees после position сбрасывает позицию.
		camera.rotation_degrees = Vector3(-65.0, 0.0, 0.0)
		camera.position = Vector3(0.0, 30.0, 18.0)
	else:
		camera.position = Vector3(0.0, 1.5, 2.0)
		camera.look_at(Vector3(0.0, 0.8, -10.0))
	camera.current = true
	print("камера: pos=%s rot=%s" % [camera.global_position, camera.rotation_degrees])
	await process_frame
	await create_timer(0.2).timeout
	print(
		"env: bg=%d fog=%s density=%.4f height=%.3f@%.1f sky_affect=%s"
		% [
			env.background_mode, env.fog_enabled, env.fog_density,
			env.fog_height_density, env.fog_height, env.fog_sky_affect,
		]
	)
	var image := view.get_texture().get_image()
	var path: String = params.get("out", "/tmp/fog_lab.png")
	image.save_png(path)
	print("сохранено: " + path)
	quit(0)
