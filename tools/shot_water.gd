# Проверка воды (vfx-fix, баг 4 и визуальный блок а): три кадра одного
# и того же вида на озеро с интервалом 0.5 с. Кадры обязаны плавно
# различаться — волна и рябь идут; копланарные плоскости (z-fighting,
# баг 4) вместо этого шумят хаотично. Сценой, а не -s: в SceneTree-режиме
# без автолоадов не компилируются island.gd/player.gd, а рендер-буфер
# между get_image() не обновляется — кадры выходят одинаковыми.
# Запуск (сервер без экрана):
#   xvfb-run -a godot --path . --resolution 1280x720 \
#     --rendering-driver opengl3 res://tools/shot_water.tscn -- <dir>
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
	# Свет и небо — упрощённый вариант мира: воде нужны свет для бликов.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
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
	# Южный берег озера (центр 6, 82, размер 30 м): озеро в кадре целиком.
	camera.global_position = Vector3(6.0, 5.5, 67.0)
	camera.look_at(Vector3(6.0, -0.15, 84.0))
	await get_tree().create_timer(delay).timeout  # IslandView строит рельеф
	for i: int in 3:
		await get_tree().create_timer(0.5).timeout
		var image := get_viewport().get_texture().get_image()
		image.save_png(out_dir.path_join("water_t%d.png" % i))
		print("кадр %d сохранён" % i)
	get_tree().quit()
