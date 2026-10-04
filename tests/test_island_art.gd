# Тесты запечённого визуала острова (этап П4.5): IslandArt.build() из данных
# IslandGen — рельеф TerrainBuilder (цвет на грань, материал по высоте),
# меши предметов PropMeshes (огранённые, «ногами» в origin, детерминированы)
# и боксы коллизий только для непроходимых типов. Критерий этапа: уступы
# холмов и стены расщелины — предметы rock_wall, мостки — plank_deck.
# Всё это чистые данные и ArrayMesh, нод не нужно.
extends GutTest

const PAL: Palette = preload("res://assets/palette.tres")

## Все типы предметов генератора (порядок — как в PropMeshes.mesh).
const PROP_TYPES: PackedStringArray = [
	"tree_leafy", "tree_spruce", "bush", "boulder", "rock_pillar", "rock_wall",
	"pebble", "grass_tuft", "flower", "ruin_block", "ruin_tower", "ruin_gate",
	"ruin_column", "bench", "board", "beacon", "pier_post", "plank_deck", "boat",
]

## Кэш данных генератора между тестами (generate() дорогой, ~10 с).
static var _gen_cache: Dictionary = {}


func _island_data() -> Dictionary:
	if _gen_cache.is_empty():
		_gen_cache = IslandGen.generate()
	return _gen_cache


func _arrays(type: String, variant: int) -> Array:
	return PropMeshes.mesh(StringName(type), variant).surface_get_arrays(0)


func test_prop_meshes_have_faces_and_colors() -> void:
	# Раздел 16: предмет — огранённый меш с цветом в вершинах (без нормалей:
	# плоское затенение считает шейдер).
	for type: String in PROP_TYPES:
		var arrays: Array = _arrays(type, 0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		assert_gt(verts.size(), 0, "%s: меш не пуст" % type)
		assert_eq(colors.size(), verts.size(), "%s: цвет каждой вершине" % type)
		assert_gt(
			(arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), 0,
			"%s: есть грани" % type,
		)
		assert_null(arrays[Mesh.ARRAY_NORMAL], "%s: нормали не запечены" % type)


func test_prop_meshes_stand_on_ground() -> void:
	# Модели стоят «ногами» в origin (позиция предмета — точка на рельефе):
	# минимум Y у земли, а не в центре меша.
	for type: String in PROP_TYPES:
		var verts: PackedVector3Array = _arrays(type, 0)[Mesh.ARRAY_VERTEX]
		var min_y: float = verts[0].y
		var max_y: float = verts[0].y
		for vertex: Vector3 in verts:
			min_y = minf(min_y, vertex.y)
			max_y = maxf(max_y, vertex.y)
		assert_between(min_y, -0.4, 0.1, "%s: origin у земли" % type)
		# Камешек — самый низкий предмет (~0.17 м), выше только трава и цветы.
		assert_gt(max_y, 0.12, "%s: предмет выше земли" % type)


func test_prop_meshes_deterministic() -> void:
	# Детерминизм визуала: сеед меша — от (тип, вариант), не от порядка
	# вызовов; один и тот же меш собирается одинаково.
	for type: String in ["tree_leafy", "boulder", "rock_wall", "grass_tuft"]:
		var first: PackedVector3Array = _arrays(type, 2)[Mesh.ARRAY_VERTEX]
		var second: PackedVector3Array = _arrays(type, 2)[Mesh.ARRAY_VERTEX]
		assert_eq(first, second, "%s: два вызова дают равные меши" % type)
	var variants: Array = []
	for variant: int in 3:
		variants.append(_arrays("tree_spruce", variant)[Mesh.ARRAY_VERTEX])
	assert_ne(variants[0], variants[1], "варианты ели различаются")


func test_terrain_chunks_face_colored() -> void:
	# Рельеф — чанки 32 × 32 м, два треугольника на квадрат, цвет — на грань
	# (все 4 вершины квадрата одной краски — low-poly фасет).
	var chunks: Array[Mesh] = TerrainBuilder.build_chunks(_island_data())
	assert_eq(
		chunks.size(),
		TerrainBuilder.CHUNKS_PER_SIDE * TerrainBuilder.CHUNKS_PER_SIDE,
		"чанков 8 × 8",
	)
	var arrays: Array = (chunks[0] as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	assert_eq(
		verts.size(), TerrainBuilder.CHUNK * TerrainBuilder.CHUNK * 4,
		"вершин по 4 на квадрат",
	)
	assert_eq(
		(arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(),
		TerrainBuilder.CHUNK * TerrainBuilder.CHUNK * 6,
		"индексов по 6 на квадрат",
	)
	for square: int in TerrainBuilder.CHUNK * TerrainBuilder.CHUNK:
		var color: Color = colors[square * 4]
		for corner: int in 4:
			assert_eq(
				colors[square * 4 + corner], color,
				"квадрат %d покрашен одной краской" % square,
			)
	assert_null(arrays[Mesh.ARRAY_NORMAL], "нормали считает шейдер")
	# Чанки детерминированы.
	var again: Array[Mesh] = TerrainBuilder.build_chunks(_island_data())
	var again_verts: PackedVector3Array = \
		(again[0] as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(verts, again_verts, "повторная сборка чанка равна")


func test_terrain_colors_follow_height() -> void:
	# Материал рельефа (раздел 6): песок у воды, снег на вершинах.
	var data: Dictionary = _island_data()
	var heights: PackedFloat32Array = data["heights"]
	var tint: Dictionary = data["tint"]
	var sand_found := false
	var snow_found := false
	for z: int in range(-IslandGen.HALF, IslandGen.HALF + 1):
		for x: int in range(-IslandGen.HALF, IslandGen.HALF + 1):
			if tint.has(Vector2i(x, z)):
				continue
			var h: float = heights[IslandGen._idx(x, z)]
			if not sand_found and h > IslandGen.SEA_LEVEL and h < TerrainBuilder.SAND_H:
				var beach: Color = TerrainBuilder.point_color(heights, tint, x, z)
				assert_gt(beach.r, beach.b, "пляж тёплого песочного тона")
				sand_found = true
			elif not snow_found and h >= TerrainBuilder.SNOW_H:
				var peak: Color = TerrainBuilder.point_color(heights, tint, x, z)
				assert_gt(peak.r, 0.8, "вершина снежно-белая")
				assert_gt(peak.g, 0.8, "вершина снежно-белая (зелёный)")
				assert_gt(peak.b, 0.8, "вершина снежно-белая (синий)")
				snow_found = true
	assert_true(sand_found, "на острове есть пляж ниже SAND_H")
	assert_true(snow_found, "на острове есть вершины выше SNOW_H")


func test_art_groups_all_props() -> void:
	# Каждый предмет попадает ровно в один MultiMesh «тип:вариант».
	var data: Dictionary = _island_data()
	var art := IslandArt.build(data)
	var instanced := 0
	for key: String in art.prop_multimeshes:
		assert_true(key.contains(":"), "ключ группы «тип:вариант»: %s" % key)
		var multimesh: MultiMesh = art.prop_multimeshes[key]
		assert_gt(multimesh.instance_count, 0, "группа %s не пустая" % key)
		assert_eq(multimesh.mesh.get_surface_count(), 1, "группа %s с мешем" % key)
		instanced += multimesh.instance_count
	assert_eq(instanced, (data["props"] as Array).size(), "все предметы в группах")


func test_art_colliders_only_solid_types() -> void:
	# Коллизии — только у непроходимых типов (IslandGen.SOLID_TYPES);
	# трава, кусты и камешки проходимы.
	var data: Dictionary = _island_data()
	var art := IslandArt.build(data)
	var solid := 0
	for prop: Dictionary in data["props"]:
		if IslandGen.SOLID_TYPES.has(String(prop["type"])):
			solid += 1
	assert_eq(art.colliders.size(), solid, "боксов коллизий — по числу твёрдых предметов")
	for collider: Dictionary in art.colliders:
		assert_true(
			(collider["size"] as Vector3).x > 0.0
			and (collider["size"] as Vector3).y > 0.0
			and (collider["size"] as Vector3).z > 0.0,
			"размер коллизии положительный",
		)


func test_crevasse_walls_and_bridges_are_props() -> void:
	# Критерий П4.5: стены расщелины и кольца смотровых — предметы rock_wall,
	# переправы через каньон — plank_deck на опорах pier_post (не рельеф).
	var data: Dictionary = _island_data()
	var walls := 0
	var lookout_walls := 0
	var decks := 0
	var posts := 0
	for prop: Dictionary in data["props"]:
		var pos: Vector3 = prop["pos"]
		match String(prop["type"]):
			"rock_wall":
				var in_crevasse: bool = pos.x >= IslandGen.CREVASSE_X0 - 3.0 \
					and pos.x <= IslandGen.CREVASSE_X1 + 3.0 \
					and pos.z >= IslandGen.CREVASSE_Z0 - 3.0 \
					and pos.z <= IslandGen.CREVASSE_Z1 + 3.0
				if in_crevasse:
					walls += 1
				else:
					var near_lookout := false
					for lookout: Vector2i in IslandGen.LOOKOUTS:
						if Vector2(pos.x, pos.z).distance_to(lookout) <= 4.0:
							near_lookout = true
					if near_lookout:
						lookout_walls += 1
			"plank_deck":
				if pos.x >= IslandGen.BRIDGE_X[0] and pos.x <= IslandGen.BRIDGE_X[1] + 1.0 \
					and pos.z >= IslandGen.CREVASSE_Z0 - 3.0 \
					and pos.z <= IslandGen.CREVASSE_Z1 + 3.0:
					decks += 1
			"pier_post":
				if pos.z >= IslandGen.CREVASSE_Z0 and pos.z <= IslandGen.CREVASSE_Z1:
					posts += 1
	assert_gt(walls, 30, "стены расщелины — предметы rock_wall")
	assert_eq(
		lookout_walls, IslandGen.LOOKOUTS.size() * 4,
		"по четыре стены-кольца на смотровой",
	)
	assert_between(decks, 10, 24, "настилы двух мостков через каньон")
	assert_between(posts, 4, 8, "опоры мостков под настилом")
