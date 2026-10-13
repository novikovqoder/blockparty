# Диагностика мешей (П5.8, возврат): рендер байт-в-байт одинаков при разных
# позах скелета — скиннинг не работает. Проверяем:
#   1) несут ли запечённые .res-меши массивы ARRAY_BONES/ARRAY_WEIGHTS;
#   2) чем закончился бы mesh.add_surface без костей (формат вершин).
#   godot --headless --path . -s res://tools/diag_mesh_arrays.gd
extends SceneTree

const MESH_DIR: String = "res://assets/third_party/quaternius.com/" \
	+ "universal_base_characters/baked/meshes"
const PARTS: PackedStringArray = ["head_m", "legs_peasant_m",
	"top_peasant_m", "arms_peasant_m", "feet_peasant_m", "hair_long"]


func _init() -> void:
	await create_timer(0.01).timeout
	for part: String in PARTS:
		var mesh := load(MESH_DIR + "/%s.res" % part) as ArrayMesh
		if mesh == null:
			print("%s: НЕ ЗАГРУЖЕН" % part)
			continue
		for s: int in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var bones: Variant = arrays[Mesh.ARRAY_BONES]
			var weights: Variant = arrays[Mesh.ARRAY_WEIGHTS]
			var bones_desc := "нет" if bones == null else \
				("int32 %d знач." if bones is PackedInt32Array
				else "float32 %d знач." if bones is PackedFloat32Array
				else str(typeof(bones))) % [
				(bones as PackedInt32Array).size() \
				if bones is PackedInt32Array else (bones as PackedFloat32Array).size()]
			var weights_desc := "нет" if weights == null else \
				"%d знач." % (weights as PackedFloat32Array).size()
			print("%s surf %d: вершины=%d BONES: %s, WEIGHTS: %s" % [
				part, s, (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
				bones_desc, weights_desc])
			break  # первый suffices
	quit(0)
