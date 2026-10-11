# Одноразовая проверка воды (vfx-fix, баг 4): три кадра одного и того же
# вида на озеро с интервалом 0.5 с. Дальше кадры сравниваются утилитой
# tools/capsule_probe.gd: копланарные плоскости (z-fighting) шумят
# попиксельно и хаотично от кадра к кадру, спокойная волна — плавный
# систематический сдвиг. Запуск (сервер без экрана):
#   xvfb-run -a godot --path . --resolution 1280x720 \
#     --rendering-driver opengl3 -s res://tools/shot_water.gd -- <dir>
extends SceneTree

const ISLAND: PackedScene = preload("res://gameplay/world/island.tscn")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "builds/screenshots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var island := ISLAND.instantiate()
	get_root().add_child(island)
	# Свет и небо — упрощённый вариант мира: воды нужен свет для бликов.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	get_root().add_child(sun)
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	world_env.environment = env
	get_root().add_child(world_env)
	var camera := Camera3D.new()
	camera.fov = 60.0
	get_root().add_child(camera)
	# Южный берег озера (центр 6, 82, размер 30 м): озеро в кадре целиком.
	camera.global_position = Vector3(6.0, 5.5, 67.0)
	camera.look_at(Vector3(6.0, -0.15, 84.0))
	await create_timer(1.0).timeout  # IslandView строит рельеф из ресурса
	for i: int in 3:
		await create_timer(0.5).timeout
		var image := get_root().get_texture().get_image()
		image.save_png(out_dir.path_join("water_t%d.png" % i))
		print("кадр %d сохранён" % i)
	quit()
