# Проверка атмосферных частиц (vfx-fix, визуальный блок г): ночной Лес —
# светлячки; дневная Площадь — пыльца; дневной Лес — листья. Управляет
# Session.world_time (DayMath) и позицией фокуса, как сцена мира.
# Запуск (сервер без экрана):
#   xvfb-run -a godot --path . --resolution 1280x720 \
#     --rendering-driver opengl3 res://tools/shot_ambient.tscn -- <dir>
extends Node

const B: Balance = preload("res://gameplay/balance.tres")
const ISLAND: PackedScene = preload("res://gameplay/world/island.tscn")


func _ready() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "builds/screenshots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.08, 0.12)
	world_env.environment = env
	get_tree().root.add_child(world_env)
	var ambient := AmbientParticles.new()
	get_tree().root.add_child(ambient)
	ambient.setup(GraphicsQuality.Tier.HIGH)
	var camera := Camera3D.new()
	camera.fov = 60.0
	get_tree().root.add_child(camera)

	# Изолированная проверка (без острова, рендерится быстро): ночь, камера
	# горизонтально внутри поля частиц, фон — чистое ночное небо. Любой
	# тёплый пиксель в кадре — светлячок; иначе частицы не рисует рендер.
	Session.world_time = B.day_cycle_sec * 0.75
	ambient.set_focus(Vector3(-52.0, 0.0, -52.0))
	camera.global_position = Vector3(-52.0, 1.5, -52.0)
	camera.look_at(Vector3(-52.0, 1.8, -66.0))
	await get_tree().create_timer(3.0).timeout
	get_viewport().get_texture().get_image().save_png(
		out_dir.path_join("ambient_fireflies_check.png"))
	print("контроль снят")

	var island := ISLAND.instantiate()
	get_tree().root.add_child(island)
	var sun := DirectionalLight3D.new()
	get_tree().root.add_child(sun)
	await get_tree().create_timer(1.2).timeout  # IslandView строит рельеф

	# Ночь в Лесу: светлячки (is_day = false → fraction ≥ day_share).
	Session.world_time = B.day_cycle_sec * 0.75
	ambient.set_focus(Vector3(-52.0, 0.0, -52.0))
	camera.global_position = Vector3(-46.0, 2.0, -46.0)
	camera.look_at(Vector3(-58.0, 1.0, -56.0))
	await _warmup_and_snap(out_dir.path_join("ambient_fireflies.png"))

	# День на Площади: пыльца (фон — дневное небо, как его красит DayCycle).
	env.background_color = Color(0.55, 0.72, 0.92)
	Session.world_time = B.day_cycle_sec * 0.3
	ambient.set_focus(Vector3(0.0, 0.0, 4.0))
	camera.global_position = Vector3(10.0, 6.0, 18.0)
	camera.look_at(Vector3(0.0, 0.5, 2.0))
	await _warmup_and_snap(out_dir.path_join("ambient_pollen.png"))

	# День в Лесу: листья.
	Session.world_time = B.day_cycle_sec * 0.3  # фон уже дневной
	ambient.set_focus(Vector3(-52.0, 0.0, -52.0))
	camera.global_position = Vector3(-46.0, 2.2, -46.0)
	camera.look_at(Vector3(-58.0, 1.5, -56.0))
	await _warmup_and_snap(out_dir.path_join("ambient_leaves.png"))
	get_tree().quit()


## Прогрев дольше самого долгого lifetime частиц (9–11 с): за 2.5 с существует
## лишь ~30% первой партии — снимок покажет заниженную плотность.
func _warmup_and_snap(path: String) -> void:
	await get_tree().create_timer(12.0).timeout
	get_viewport().get_texture().get_image().save_png(path)
	print("атмосфера снята: ", path)
