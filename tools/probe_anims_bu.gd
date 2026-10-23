extends SceneTree
## Одноразовый пробник П10: скин меша ног героя (bind-позы, кости ног,
## сдвиг вершин покой/ходьба). Запуск:
## godot --headless --path . -s res://tools/probe_anims_bu.gd

const MODEL: Script = preload("res://gameplay/player/hero_model_bu.gd")

func _initialize() -> void:
	var model: Node = MODEL.new()
	root.add_child(model)
	var mb: Node = model
	var skel: Skeleton3D = mb.call("skeleton") as Skeleton3D
	var mi: MeshInstance3D = null
	for name: String in ["Pants", "Boots"]:
		var found: Array = skel.find_children(name, "MeshInstance3D", true, false)
		if found.size() > 0:
			mi = found[0] as MeshInstance3D
			print("legs mesh: ", mi.name)
			break
	if mi == null:
		print("нет меша ног")
		quit(0)
		return
	var skin: Skin = mi.skin
	print("skin == null: ", skin == null, " bind_count=", skin.get_bind_count() if skin else -1)
	if skin != null:
		var keys: PackedInt32Array = PackedInt32Array()
		for i: int in skin.get_bind_count():
			keys.append(skin.get_bind_bone(i))
		print("bind bones: ", keys)
	var arrays: Array = (mi.mesh as ArrayMesh).surface_get_arrays(0)
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] as PackedInt32Array
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
	var used := {}
	for v: int in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
		for j: int in 4:
			if weights[v * 4 + j] > 0.05:
				used[bones[v * 4 + j]] = true
	print("bones used (w>0.05): ", used.keys())
	for bone_name: String in ["mixamorig_LeftUpLeg", "mixamorig_LeftLeg"]:
		print(bone_name, " idx=", skel.find_bone(bone_name))
	# Позы покой/ходьба без анимации — просто манипуляция костью
	var idx: int = skel.find_bone("mixamorig_LeftLeg")
	var rest: Quaternion = skel.get_bone_pose_rotation(idx)
	skel.set_bone_pose_rotation(idx, rest * Quaternion(Vector3.LEFT, 0.7))
	print("pose changed manually, get_bone_global_pose delta ok")
	quit(0)
