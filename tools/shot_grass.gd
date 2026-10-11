# Проверка растительности (vfx-fix, визуальный блок б): кадр луга с
# травой и цветами и кадр опушки леса (деревья/кусты). Два снимка с
# разной задержкой (delay из аргументов) обязаны различаться — ветер
# качает траву; трава на лугу — плотная. Запуск (сервер без экрана):
#   xvfb-run -a godot --path . --resolution 1280x720 \
#     --rendering-driver opengl3 res://tools/shot_grass.tscn -- <dir> [--delay=S]
extends Node

const ISLAND: PackedScene = preload("res://gameplay/world/island.tscn")


func _ready() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "builds/screenshots"
	var delay := 1.0
	for arg: String in args:
		if arg.begins_with("--delay="):
			delay = arg.substr("--delay=".length()).to_float()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var island := ISLAND.instantiate()
	get_tree().root.add_child(island)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	get_tree().root.add_child(sun)
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	world_env.environment = env
	get_tree().root.add_child(world_env)
	var camera := Camera3D.new()
	camera.fov = 60.0
	get_tree().root.add_child(camera)
	await get_tree().create_timer(delay).timeout  # IslandView строит рельеф
	# Луг к востоку от площади (трава/цветы): вид с высоты глаз, наклонён вниз.
	camera.global_position = Vector3(24.0, 2.2, 16.0)
	camera.look_at(Vector3(34.0, 0.5, 24.0))
	await get_tree().create_timer(0.3).timeout
	get_viewport().get_texture().get_image().save_png(
		out_dir.path_join("grass_meadow.png"))
	print("луг снят")
	# Опушка леса (деревья, кусты, трава).
	camera.global_position = Vector3(40.0, 2.0, -30.0)
	camera.look_at(Vector3(48.0, 2.5, -38.0))
	await get_tree().create_timer(0.3).timeout
	get_viewport().get_texture().get_image().save_png(
		out_dir.path_join("grass_forest_edge.png"))
	print("опушка снята")
	get_tree().quit()
