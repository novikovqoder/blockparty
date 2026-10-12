# Одноразовая диагностика (П5.8, часть B): полный список костей рига UBC.
# Запуск: godot --headless -s tools/dump_ubc_bones.gd -- <файл.gltf>
extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("нет файлов")
		quit(1)
		return
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(args[0], state) != OK:
		print("не читается")
		quit(1)
		return
	var root := doc.generate_scene(state)
	_bones(root)
	root.free()
	quit(0)


func _bones(node: Node) -> void:
	if node is Skeleton3D:
		var skeleton := node as Skeleton3D
		for i: int in skeleton.get_bone_count():
			print("%d %s" % [i, skeleton.get_bone_name(i)])
		return
	for child: Node in node.get_children():
		_bones(child)
