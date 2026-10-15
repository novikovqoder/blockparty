# Д4 (тело под одеждой): состав поверхностей запечённых частей — материалы
# (кожа/ткань), вершины и кости с весами. Показывает, где в частях MCO
# живёт «тело» (skin_*) и что может просвечивать сквозь ткань на сгибах.
#   godot --headless --path . -s res://tools/probe_part_surfaces.gd
extends SceneTree

const MESH_DIR: String = "res://assets/third_party/quaternius.com/" \
	+ "universal_base_characters/baked/meshes"
const PARTS: PackedStringArray = [
	"head_m", "head_f",
	"top_peasant_m", "arms_peasant_m", "legs_peasant_m", "feet_peasant_m",
	"top_peasant_f", "arms_peasant_f", "legs_peasant_f", "feet_peasant_f",
	"top_ranger_m", "arms_ranger_m", "legs_ranger_m", "feet_ranger_m",
	"top_ranger_f", "arms_ranger_f", "legs_ranger_f", "feet_ranger_f",
	"hood_ranger_m", "hood_ranger_f",
]


func _init() -> void:
	await create_timer(0.01).timeout
	for part: String in PARTS:
		var mesh := load("%s/%s.res" % [MESH_DIR, part]) as ArrayMesh
		if mesh == null:
			print("%s: НЕ ЗАГРУЖЕН" % part)
			continue
		print("== %s" % part)
		for s: int in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var mat := mesh.surface_get_material(s) as StandardMaterial3D
			var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var name := mat.resource_name if mat != null else "?"
			# Сводка весов по костям: имя кости → сумма весов (из _skin.res
			# имена недоступны, индексы костей общие для рига UBC).
			var bones := arrays[Mesh.ARRAY_BONES] as PackedInt32Array
			var weights := arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
			var vw: int = weights.size() / maxi(verts.size(), 1)
			var per_bone := {}
			for v: int in verts.size():
				for k: int in vw:
					var w: float = weights[v * vw + k]
					if w > 0.01:
						per_bone[bones[v * vw + k]] = \
							float(per_bone.get(bones[v * vw + k], 0.0)) + w
			var top := []
			for bone: int in per_bone.keys():
				top.append([bone, per_bone[bone]])
			top.sort_custom(func(a, b) -> bool: return a[1] > b[1])
			var top_names: Array[String] = []
			for i: int in mini(6, top.size()):
				top_names.append("%d:%.0f" % [top[i][0], top[i][1]])
			print("  surf %d %-14s verts %5d  кости %s" % [
				s, name, verts.size(), " ".join(top_names)])
	quit(0)
