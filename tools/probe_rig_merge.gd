# Одноразовая диагностика (П5.8, часть B): можно ли собрать персонажа из
# частей UBC+MCO на ОДИН скелет в рантайме Godot — перенести меши одежды
# под Skeleton3D тела UBC — и проиграть клип UAL без ретаргетинга
# (риг 65 костей идентичен). Снимает 4 кадра: покой и 3 момента Idle.
# Запуск: xvfb-run -a godot --path . --resolution 1280x720 \
#   --rendering-driver opengl3 res://tools/probe_rig_merge.tscn -- <каталог>
extends Node

const UBC := ".downloads/ubc/Universal Base Characters[Standard]"
const MCO := ".downloads/mco/Modular Character Outfits - Fantasy[Standard]/Exports/glTF (Godot-Unreal)"
const UAL1 := "res://builds/ual_probe/UAL1.glb"  # импортированная копия из П5.7

## Части, чьи меши переезжают под скелет тела UBC (меш тела потом скрыт).
const TRANSFER_PARTS: PackedStringArray = [
	MCO + "/Modular Parts/Male_Peasant_Body.gltf",
	MCO + "/Modular Parts/Male_Peasant_Arms.gltf",
	MCO + "/Modular Parts/Male_Peasant_Legs.gltf",
	MCO + "/Modular Parts/Male_Peasant_Feet.gltf",
	UBC + "/Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)/Hair_SimpleParted.gltf",
]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "builds/rig_probe"
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred(out_dir)


func _run(out_dir: String) -> void:
	var root := get_tree().root

	# Сцена: свет и фон как в прошлом стенде.
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

	# 1) Тело UBC — главный скелет. Меш тела прячем (одежда закрывает всё).
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(
		UBC + "/Base Characters/Godot - UE/Superhero_Male_FullBody.gltf", state)
	if err != OK:
		push_error("нет UBC: %d" % err)
		get_tree().quit(1)
		return
	var body_scene: Node = doc.generate_scene(state)
	root.add_child(body_scene)
	print("UBC сцена: ", body_scene.name, " дети: ",
		[child.name for child in body_scene.get_children()])
	var skeleton := _find_first_of(body_scene, "Skeleton3D") as Skeleton3D
	print("скелет: ", skeleton.get_path_from(root) if skeleton else "НЕТ",
		", костей: ", skeleton.get_bone_count() if skeleton else -1)
	var body_mesh := _find_first_of(body_scene, "MeshInstance3D") as MeshInstance3D
	# Прячем именно меш «SuperHero_Male» (первый MeshInstance3D может быть глазами).
	for mi in _find_all(body_scene, "MeshInstance3D"):
		if String(mi.name).begins_with("SuperHero"):
			mi.visible = false
			body_mesh = mi
	print("меш тела скрыт: ", body_mesh.name)

	# 2) Меши частей MCO/волос — под тот же скелет.
	for path in TRANSFER_PARTS:
		var pdoc := GLTFDocument.new()
		var pstate := GLTFState.new()
		if pdoc.append_from_file(path, pstate) != OK:
			push_error("не читается: " + path)
			continue
		var part: Node = pdoc.generate_scene(pstate)
		for mi in _find_all(part, "MeshInstance3D"):
			var mesh_inst := mi as MeshInstance3D
			var old_path := mesh_inst.get_path()
			mesh_inst.reparent(skeleton)
			mesh_inst.name = String(mesh_inst.name)
			print("перенесён: %s → %s (skeleton=%s)" % [old_path,
				mesh_inst.get_path_from(root), str(mesh_inst.skeleton)])
		part.queue_free()

	await get_tree().process_frame

	# 3) Клип UAL на общий риг: пути треков «Armature/Skeleton3D/кость» —
	# подгоняем под фактический корень body_scene.
	var adoc := GLTFDocument.new()
	var astate := GLTFState.new()
	if adoc.append_from_file(UAL1, astate) != OK:
		push_error("нет UAL")
		get_tree().quit(1)
		return
	var lib := AnimationLibrary.new()
	var anim_root := body_scene.name  # ожидаем «Armature»
	for anim_name in ["Idle_Loop", "Walk_Loop", "Wave_Hand"]:
		pass  # Wave_Hand нет в UAL; ниже берём только существующие
	var take_names: PackedStringArray = []
	for lib_name in astate.get_animations():
		take_names.append(lib_name)
	print("клипов в UAL1: ", take_names.size())
	for anim in astate.get_animations():
		var fixed := anim.duplicate() as Animation
		for ti in fixed.get_track_count():
			var path_str: String = fixed.track_get_path(ti)
			if path_str.begins_with("Armature/"):
				fixed.track_set_path(ti, anim_root + path_str.substr("Armature".length()))
		lib.add_animation(String(anim.resource_name), fixed)
	var player := AnimationPlayer.new()
	body_scene.add_sibling(player)
	player.name = "AnimPlayer"
	player.root_node = player.get_path_to(root)
	player.add_animation_library("", lib)
	player.play("Idle_Loop")
	print("играет Idle_Loop, длительность ",
		player.current_animation_length)

	# 4) Кадры: до анимации и три момента.
	camera.global_position = Vector3(1.6, 1.1, 3.2)
	camera.look_at(Vector3(0.0, 0.95, 0.0))
	await get_tree().create_timer(0.3).timeout
	_shot(out_dir + "/idle_t000.png", camera)
	for t in [0.4, 0.9, 1.4]:
		await get_tree().create_timer(t).timeout
		_shot(out_dir + ("/idle_t%03d.png" % int((t + 0.3) * 100)), camera)
	# Прогон Walk: если ходьба не разваливается — перенос скинов валиден.
	player.play("Walk_Loop")
	await get_tree().create_timer(0.2).timeout
	_shot(out_dir + "/walk_t020.png", camera)
	await get_tree().create_timer(0.8).timeout
	_shot(out_dir + "/walk_t100.png", camera)
	print("снято 6 кадров в ", out_dir)
	get_tree().quit(0)


func _shot(file: String, camera: Camera3D) -> void:
	var img := camera.get_viewport().get_texture().get_image()
	img.save_png(file)
	print("снято: %s" % file)


func _find_first_of(node: Node, classname: String) -> Node:
	if node.is_class(classname):
		return node
	for child in node.get_children():
		var found := _find_first_of(child, classname)
		if found:
			return found
	return null


func _find_all(node: Node, classname: String) -> Array[Node]:
	var res: Array[Node] = []
	if node.is_class(classname):
		res.append(node)
	for child in node.get_children():
		res.append_array(_find_all(child, classname))
	return res
