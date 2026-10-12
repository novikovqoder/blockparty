# Одноразовая диагностика (П5.8, часть E): rest-геометрия головы UBC —
# индекс кости Head, AABB меша головы по полам, посадка уборов.
extends SceneTree

func _init() -> void:
	for g: String in ["m", "f"]:
		var scene := load("res://assets/third_party/quaternius.com/universal_base_characters/baked/ubc_%s.res" % ("male" if g == "m" else "female")) as PackedScene
		var root := scene.instantiate()
		var sk := root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var head_idx := sk.find_bone("Head")
		print("%s: Head idx=%d global_rest_origin=%s rest_origin=%s"
			% [g, head_idx, sk.get_bone_global_rest(head_idx).origin, sk.get_bone_rest(head_idx).origin])
		for part in ["head_%s" % g, "hair_long", "hair_simple_parted", "hair_beard", "hair_buns"]:
			for n in root.find_children(part, "MeshInstance3D", true, false):
				var mi := n as MeshInstance3D
				var aabb := mi.mesh.get_aabb()
				print("  %s aabb=%s..%s tris=%d" % [part, aabb.position, aabb.end, (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3])
		root.free()
	quit(0)
