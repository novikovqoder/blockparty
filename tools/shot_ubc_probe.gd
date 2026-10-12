# Одноразовая диагностика (П5.8, часть B): снимает тела UBC с одеждой MCO
# в нейтральной постановке — видно пропорции и посадку модулей.
# Запуск: xvfb-run -a godot --path . --resolution 1280x720 \
#   --rendering-driver opengl3 res://tools/shot_ubc_probe.tscn -- <каталог>
extends Node

const UBC := ".downloads/ubc/Universal Base Characters[Standard]/Base Characters/Godot - UE"
const MCO := ".downloads/mco/Modular Character Outfits - Fantasy[Standard]/Exports/glTF (Godot-Unreal)"

## Тело + модули одной позицией кадра: имя → список gltf от корня проекта.
const SHOTS: Array[Dictionary] = [
	{"name": "body_male", "parts": [UBC + "/Superhero_Male_FullBody.gltf"]},
	{"name": "body_female", "parts": [UBC + "/Superhero_Female_FullBody.gltf"]},
	{
		"name": "peasant_male",
		"parts": [
			UBC + "/Superhero_Male_FullBody.gltf",
			MCO + "/Modular Parts/Male_Peasant_Arms.gltf",
			MCO + "/Modular Parts/Male_Peasant_Body.gltf",
			MCO + "/Modular Parts/Male_Peasant_Legs.gltf",
			MCO + "/Modular Parts/Male_Peasant_Feet.gltf",
		],
	},
	{
		# Комплект сам по себе, без тела UBC: сквозные дыры видны на фоне.
		"name": "peasant_male_mco",
		"parts": [
			MCO + "/Modular Parts/Male_Peasant_Arms.gltf",
			MCO + "/Modular Parts/Male_Peasant_Body.gltf",
			MCO + "/Modular Parts/Male_Peasant_Legs.gltf",
			MCO + "/Modular Parts/Male_Peasant_Feet.gltf",
		],
	},
	{
		"name": "ranger_male_mco",
		"parts": [
			MCO + "/Modular Parts/Male_Ranger_Arms.gltf",
			MCO + "/Modular Parts/Male_Ranger_Body.gltf",
			MCO + "/Modular Parts/Male_Ranger_Legs.gltf",
			MCO + "/Modular Parts/Male_Ranger_Feet_Boots.gltf",
			MCO + "/Modular Parts/Male_Ranger_Head_Hood.gltf",
		],
	},
	{
		"name": "peasant_female_mco",
		"parts": [
			MCO + "/Modular Parts/Female_Peasant_Arms.gltf",
			MCO + "/Modular Parts/Female_Peasant_Body.gltf",
			MCO + "/Modular Parts/Female_Peasant_Legs.gltf",
			MCO + "/Modular Parts/Female_Peasant_Feet.gltf",
		],
	},
	{
		"name": "ranger_male",
		"parts": [
			UBC + "/Superhero_Male_FullBody.gltf",
			MCO + "/Modular Parts/Male_Ranger_Arms.gltf",
			MCO + "/Modular Parts/Male_Ranger_Body.gltf",
			MCO + "/Modular Parts/Male_Ranger_Legs.gltf",
			MCO + "/Modular Parts/Male_Ranger_Feet_Boots.gltf",
			MCO + "/Modular Parts/Male_Ranger_Head_Hood.gltf",
		],
	},
	{
		"name": "peasant_female",
		"parts": [
			UBC + "/Superhero_Female_FullBody.gltf",
			MCO + "/Modular Parts/Female_Peasant_Arms.gltf",
			MCO + "/Modular Parts/Female_Peasant_Body.gltf",
			MCO + "/Modular Parts/Female_Peasant_Legs.gltf",
			MCO + "/Modular Parts/Female_Peasant_Feet.gltf",
		],
	},
	{
		"name": "ranger_female",
		"parts": [
			UBC + "/Superhero_Female_FullBody.gltf",
			MCO + "/Modular Parts/Female_Ranger_Arms.gltf",
			MCO + "/Modular Parts/Female_Ranger_Body.gltf",
			MCO + "/Modular Parts/Female_Ranger_Legs.gltf",
			MCO + "/Modular Parts/Female_Ranger_Feet.gltf",
			MCO + "/Modular Parts/Female_Ranger_Head_Hood.gltf",
		],
	},
]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "builds/ubc_probe"
	DirAccess.make_dir_recursive_absolute(out_dir)
	_shots.call_deferred(out_dir)


func _shots(out_dir: String) -> void:
	var root := get_tree().root
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.22, 0.24, 0.28)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.57, 0.62)
	env.ambient_light_energy = 1.0
	world_env.environment = env
	root.add_child(world_env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35.0, -30.0, 0.0)
	key.light_energy = 2.2
	root.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20.0, 150.0, 0.0)
	rim.light_energy = 1.1
	rim.light_color = Color(0.7, 0.8, 1.0)
	root.add_child(rim)

	var camera := Camera3D.new()
	camera.fov = 40.0
	root.add_child(camera)
	await get_tree().process_frame

	for shot: Dictionary in SHOTS:
		var holder := Node3D.new()
		root.add_child(holder)
		for path: String in shot["parts"]:
			var doc := GLTFDocument.new()
			var state := GLTFState.new()
			if doc.append_from_file(path, state) != OK:
				push_error("не читается: " + path)
				continue
			holder.add_child(doc.generate_scene(state))
		await get_tree().process_frame
		camera.global_position = Vector3(1.6, 1.1, 3.2)
		camera.look_at(Vector3(0.0, 0.95, 0.0))
		await get_tree().create_timer(0.3).timeout
		var img := get_viewport().get_texture().get_image()
		var file := out_dir.path_join(String(shot["name"]) + ".png")
		img.save_png(file)
		print("снято: %s" % file)
		holder.queue_free()
		await get_tree().process_frame
	get_tree().quit(0)
