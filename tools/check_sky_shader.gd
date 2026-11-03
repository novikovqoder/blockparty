# Проверка (П17 п.9): проектная копия шейдера неба компилируется под
# реальным рендером (llvmpipe + Xvfb) — FRAGCOORD в sky-шейдере и
# res://-инклуд Common. Риг неба берётся из сцены мира (материал — копия);
# presentation не нужен: кадр рисуется force_draw (по памятке съёмок).
# Запуск: xvfb-run -a godot --path . -s tools/check_sky_shader.gd
# (без --headless: нужен реальный рендер llvmpipe; ошибки компиляции
# шейдера Godot печатает в вывод — обёртка их грепает).
extends SceneTree


func _initialize() -> void:
	var scene: Node = load("res://scenes/world_scene.tscn").instantiate()
	# Риг неба переносим в root (сам WorldScene не добавляем: его _ready
	# поднимает HUD и сеть — для компиляции шейдера нужен только риг).
	var env: WorldEnvironment = scene.get_node("WorldEnvironment")
	env.get_parent().remove_child(env)
	root.add_child(env)
	var cam := Camera3D.new()
	cam.name = "CheckCam"
	root.add_child(cam)
	cam.current = true
	cam.global_position = Vector3(0.0, 12.0, 30.0)
	RenderingServer.render_loop_enabled = false
	for i: int in 6:
		RenderingServer.force_draw(true)
	print("SKY-CHECK: frames drawn with project sky material")
	env.queue_free()
	scene.free()
	quit(0)
