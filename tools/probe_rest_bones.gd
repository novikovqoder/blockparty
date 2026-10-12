# Одноразовая диагностика (П5.8, часть B): позиции ключевых костей покоя
# у UBC-тела и MCO-частей — проверка, под какие пропорции сделана одежда.
# Запуск: godot --headless -s tools/probe_rest_bones.gd -- <файл.gltf> [...]
extends SceneTree

const KEYS: PackedStringArray = ["Hips", "Spine", "Head", "HeadTop_End",
	"LeftArm", "RightArm", "LeftUpLeg", "RightUpLeg", "LeftFoot", "RightFoot"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("нет файлов")
		quit(1)
		return
	for path in args:
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(path, state) != OK:
			print("%s: не читается" % path)
			continue
		var root := doc.generate_scene(state)
		var skeleton := _find_skeleton(root)
		if skeleton == null:
			print("%s: нет скелета" % path)
			root.free()
			continue
		print(path.get_file())
		for key in KEYS:
			var idx := skeleton.find_bone(key)
			if idx < 0:
				print("  %s: НЕТ" % key)
				continue
			var p := skeleton.get_bone_global_rest(idx).origin
			print("  %-12s y=%.4f x=%+.4f" % [key, p.y, p.x])
		# ширина плеч по концевым костям
		var l := skeleton.find_bone("LeftHand")
		var r := skeleton.find_bone("RightHand")
		if l >= 0 and r >= 0:
			var pl := skeleton.get_bone_global_rest(l).origin
			var pr := skeleton.get_bone_global_rest(r).origin
			print("  размах рук (локти-кисти): %.4f" % absf(pl.x - pr.x))
		root.free()
	quit(0)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null
