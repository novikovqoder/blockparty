# Проверка (П17 п.4 «Туман крон»): canopy- и impostor-шейдеры с fog()
# компилируются под реальным рендером (llvmpipe + Xvfb) — запись в FOG и
# пользовательская fog() с аргументами могли быть отвергнуты на этапе
# GLSL-компиляции, а headless-тесты код шейдера только разбирают.
# Запуск: xvfb-run -a godot --path . -s tools/check_tree_fog_shader.gd
# (без --headless: нужен реальный рендер; ошибки компиляции шейдера Godot
# печатает в вывод — обёртка их грепает).
extends SceneTree


func _initialize() -> void:
	var cam := Camera3D.new()
	cam.name = "CheckCam"
	root.add_child(cam)
	cam.current = true
	cam.position = Vector3(0.0, 6.0, 20.0)
	# По кваду на шейдер: материальные сэмплеры не назначаем — компиляция
	# идёт и на дефолтных (белых) текстурах, важен сам код.
	for path: String in [
			"res://assets/shaders/canopy.gdshader",
			"res://assets/shaders/impostor.gdshader"]:
		var quad := MeshInstance3D.new()
		quad.name = "Quad" + path.get_file().get_basename()
		quad.mesh = QuadMesh.new()
		quad.position = Vector3(0.0, 4.0, 0.0) \
				if quad.name == "Quadcanopy" else Vector3(6.0, 4.0, 0.0)
		var material := ShaderMaterial.new()
		material.shader = load(path)
		quad.material_override = material
		root.add_child(quad)
	RenderingServer.render_loop_enabled = false
	for i: int in 6:
		RenderingServer.force_draw(true)
	print("TREE-FOG-CHECK: frames drawn with canopy+impostor materials")
	quit(0)
