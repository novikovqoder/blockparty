# Тесты «земля видна» (шаг 1 П4.5): регресс на класс бага «пропавшая земля»
# — рельеф под ногами стал прозрачным. Проверяется не картинка, а её причины
# из чек-листа шага: обход треугольников и нормали (грань видна сверху),
# непрозрачность материала рельефа, видимость узла и попадание визуального
# слоя в cull_mask игровой камеры. Высоты меша и коллизии совпадают —
# отдельным тестом в test_island_scene (map_data == heights генератора).
extends GutTest

const ISLAND: PackedScene = preload("res://gameplay/world/island.tscn")
const PLAYER: PackedScene = preload("res://gameplay/player/player.tscn")

## Нормаль вверх: средняя по граням зоны должна смотреть в небо (y > 0.5),
## даже с крутыми склонами и стеной каньона.
const UP_Y: float = 0.5


func _terrain_meshes(island: Island) -> Array[MeshInstance3D]:
	var view := island.get_node("IslandView") as IslandView
	var meshes: Array[MeshInstance3D] = []
	for child: Node in view.get_node("Terrain").get_children():
		if child is MeshInstance3D:
			meshes.append(child)
	return meshes


func test_terrain_faces_point_up_in_every_zone() -> void:
	# Нормали в меше рельефа не пишутся (их считает шейдер по производным) —
	# геометрическую нормаль считаем из обхода треугольника: если порядок
	# вершин перевернётся (грань видна только снизу), средняя нормаль зоны
	# уйдёт в минус и тест поймает это.
	var island := ISLAND.instantiate() as Island
	add_child_autofree(island)
	for zone: Dictionary in island.zones:
		var center: Vector2 = zone["center"]
		var radius: float = zone["radius"]
		var sum := Vector3.ZERO
		var faces := 0
		for mesh_instance: MeshInstance3D in _terrain_meshes(island):
			var arrays: Array = (mesh_instance.mesh as ArrayMesh).surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for t: int in range(0, indices.size(), 3):
				var a: Vector3 = verts[indices[t]]
				var b: Vector3 = verts[indices[t + 1]]
				var c: Vector3 = verts[indices[t + 2]]
				var centroid := (a + b + c) / 3.0
				if Vector2(centroid.x, centroid.z).distance_to(center) > radius:
					continue
				sum += (b - a).cross(c - a)
				faces += 1
		assert_gt(faces, 100, "в зоне %s хватает граней для проверки" % zone["name"])
		var mean := sum / float(faces)
		assert_gt(
			mean.normalized().y, UP_Y,
			"зона %s: средняя нормаль рельефа смотрит вверх (y=%.2f)"
			% [zone["name"], mean.normalized().y],
		)


func test_terrain_material_is_opaque() -> void:
	# Материал рельефа непрозрачен в обеих ветках LowPolyMat: плоский
	# StandardMaterial3D (headless) без прозрачности и с альфой 1, а шейдер
	# lowpoly не пишет ALPHA и не включает blend-режимы прозрачности.
	var island := ISLAND.instantiate() as Island
	add_child_autofree(island)
	var material: Material = _terrain_meshes(island)[0].material_override
	assert_not_null(material, "у рельефа назначен материал")
	if material is StandardMaterial3D:
		var flat := material as StandardMaterial3D
		assert_eq(
			flat.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED,
			"плоский материал рельефа без прозрачности",
		)
		assert_almost_eq(flat.albedo_color.a, 1.0, 0.001, "альфа = 1")
	elif material is ShaderMaterial:
		assert_eq(
			(material as ShaderMaterial).shader.resource_path,
			LowPolyMat.SHADER.resource_path,
			"шейдер рельефа — общий lowpoly",
		)
	else:
		fail_test("неизвестный материал рельефа: %s" % material)
	var code: String = LowPolyMat.SHADER.code
	assert_false(
		"ALPHA" in code, "шейдер lowpoly не пишет ALPHA (прозрачность)",
	)
	for mode: String in ["blend_add", "blend_sub", "blend_mul", "depth_prepass_alpha"]:
		assert_false(
			("render_mode %s" % mode) in code or (", %s" % mode) in code,
			"render_mode без %s" % mode,
		)


func test_terrain_visible_and_in_camera_cull_mask() -> void:
	# Узел рельефа видим, меши — на ненулевом визуальном слое, и этот слой
	# попадает в cull_mask камеры игрока (маска 1 по умолчанию).
	var island := ISLAND.instantiate() as Island
	add_child_autofree(island)
	var player := PLAYER.instantiate() as Player
	island.add_child(player)
	var camera := player.find_children("*", "Camera3D")[0] as Camera3D
	assert_not_null(camera, "у игрока есть камера")
	var terrain := island.get_node("IslandView/Terrain")
	assert_true(terrain.visible, "узел Terrain видим")
	var layers_or: int = 0
	for mesh_instance: MeshInstance3D in _terrain_meshes(island):
		assert_true(mesh_instance.visible, "меш чанка рельефа видим")
		assert_true(mesh_instance.layers != 0, "меш чанка на ненулевом слое")
		layers_or |= mesh_instance.layers
	assert_true(
		layers_or != 0 and (camera.cull_mask & layers_or) != 0,
		"слой рельефа (%d) попадает в cull_mask камеры (%d)"
		% [layers_or, camera.cull_mask],
	)
	player.queue_free()
