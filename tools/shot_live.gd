# Проверка живых источников (vfx-fix, визуальный блок д): ночной костёр
# (шейдерное пламя, искры, мерцающий свет) и зажжённый маяк с вращающимся
# световым конусом («Высокое качество»). Тайминг ночи — DayMath по
# Session.world_time, как в сцене мира.
# Запуск (сервер без экрана):
#   xvfb-run -a godot --path . --resolution 1280x720 \
#     --rendering-driver opengl3 res://tools/shot_live.tscn -- <dir>
extends Node

const B: Balance = preload("res://gameplay/balance.tres")
const ISLAND: PackedScene = preload("res://gameplay/world/island.tscn")

## Позиции узлов island.tscn: костёр на Площади, Beacon1 у Леса.
const CAMPFIRE_POS := Vector3(0.5, 2.0, 2.5)
const BEACON1_POS := Vector3(-59.5, 4.59, -39.5)


func _ready() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "builds/screenshots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	# Конус маяка живёт только в «Высоком качестве» (GraphicsQuality).
	Settings.high_quality = true
	var island := ISLAND.instantiate()
	get_tree().root.add_child(island)
	var sun := DirectionalLight3D.new()
	get_tree().root.add_child(sun)
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.08, 0.12)
	world_env.environment = env
	get_tree().root.add_child(world_env)
	var camera := Camera3D.new()
	camera.fov = 60.0
	get_tree().root.add_child(camera)
	await get_tree().create_timer(1.2).timeout  # IslandView строит рельеф

	# Ночь: и мерцание костра, и луч маяка видны только в темноте.
	Session.world_time = B.day_cycle_sec * 0.75

	# Костёр крупно: поленья, угли, пламя; камера у самой земли.
	camera.global_position = CAMPFIRE_POS + Vector3(2.6, 0.9, 3.0)
	camera.look_at(CAMPFIRE_POS + Vector3(0.0, 0.4, 0.0))
	await get_tree().create_timer(2.0).timeout
	get_viewport().get_texture().get_image().save_png(
		out_dir.path_join("live_campfire.png"))
	print("костёр снят")

	# Маяк: зажечь напрямую (сетевой путь не нужен для картинки). Стартовый
	# поворот конуса подобран так, что за паузу 0.3 с (доверот ~15°) пятно
	# приходит на траву между башней и камерой.
	var beacon := _beacon1(island)
	beacon.set_lit(true)
	camera.global_position = BEACON1_POS + Vector3(-14.0, 5.0, 10.0)
	camera.look_at(BEACON1_POS + Vector3(0.0, 3.0, 0.0))
	beacon._cone.rotation.y = 1.92
	await get_tree().create_timer(0.3).timeout
	get_viewport().get_texture().get_image().save_png(
		out_dir.path_join("live_beacon.png"))
	print("маяк снят")
	get_tree().quit()


## Beacon1 по имени узла (порядок _beacons у IslandGen).
func _beacon1(root: Node) -> Beacon:
	return root.get_node(^"Beacon1") as Beacon
