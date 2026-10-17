# Тесты запечённого визуала острова (этап П4.5): IslandArt.build() из данных
# IslandGen — рельеф TerrainBuilder (цвет на грань, материал по высоте),
# меши предметов PropMeshes (огранённые, «ногами» в origin, детерминированы)
# и боксы коллизий только для непроходимых типов. Критерий этапа: уступы
# холмов и стены расщелины — предметы rock_wall, мостки — plank_deck.
# Всё это чистые данные и ArrayMesh, нод не нужно.
extends GutTest

const PAL: Palette = preload("res://assets/palette.tres")

## Все типы предметов генератора (порядок — как в PropMeshes.mesh;
## CC0-модели kenney.nl — через Cc0Meshes, см. assets/third_party/LICENSES.md;
## etree_*/dead_log — процедурные деревья TreeGen, П5.9 блок 4).
const PROP_TYPES: PackedStringArray = [
	"tree_leafy", "tree_spruce", "bush", "fern",
	"log_bridge", "boulder", "rock_pillar", "rock_wall",
	"pebble", "grass_tuft", "flower", "reed", "ruin_block", "ruin_tower",
	"ruin_gate", "ruin_arch", "ruin_column", "bench", "board", "beacon",
	"pier_post", "plank_deck", "boat",
	"etree_pine", "etree_oak", "etree_aspen", "etree_bush", "etree_giant",
	"dead_log", "rrock", "rgrass", "rflower", "riris", "mrock",
]

## Лесная растительность П5.9 с запечёнными нормалями: трава, папоротник
## и цветы — Vector3.UP (пучок затеняется как земля, а не как вертикальная
## стенка), камни во мху — сглаженные (мягкая форма, не фасет).
const FOREST_BAKED_NORMALS: PackedStringArray = [
	"rgrass", "rflower", "riris", "fern", "mrock", "rrock",
]

## Процедурные деревья и валежник Леса (П5.9, блок 4): нормали запечены
## (кора — радиальные, крона — скруглённые к объёму), у деревьев две
## поверхности — кора с CC0-текстурой и крона canopy.gdshader.
const ETREE_TYPES: PackedStringArray = [
	"etree_pine", "etree_oak", "etree_aspen", "etree_bush", "etree_giant",
	"dead_log",
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
	# плоское затенение считает шейдер). Исключения — лесная растительность
	# П5.9 (FOREST_BAKED_NORMALS) и деревья TreeGen (ETREE_TYPES, нормали
	# нужны их материалам); у последних по две поверхности — все проверяются.
	for type: String in PROP_TYPES:
		var mesh := PropMeshes.mesh(StringName(type), 0)
		for surface: int in mesh.get_surface_count():
			var label := "%s/%d" % [type, surface]
			var arrays: Array = mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			assert_gt(verts.size(), 0, "%s: меш не пуст" % label)
			assert_eq(colors.size(), verts.size(), "%s: цвет каждой вершине" % label)
			assert_gt(
				(arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), 0,
				"%s: есть грани" % label,
			)
			if FOREST_BAKED_NORMALS.has(type) or ETREE_TYPES.has(type):
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				assert_eq(normals.size(), verts.size(), "%s: нормаль каждой вершине" % label)
				for normal: Vector3 in normals:
					assert_almost_eq(
						normal.length(), 1.0, 0.001, "%s: нормали единичные" % label
					)
			else:
				assert_null(arrays[Mesh.ARRAY_NORMAL], "%s: нормали не запечены" % label)


func test_prop_meshes_stand_on_ground() -> void:
	# Модели стоят «ногами» в origin (позиция предмета — точка на рельефе):
	# минимум Y у земли, а не в центре меша. Деревья TreeGen стоят в origin
	# осью ствола: нижнее кольцо коры уходит вниз на радиус (у гиганта
	# радиус ~0.6 м — ствол «врастает» в землю, это норма).
	for type: String in PROP_TYPES:
		var verts: PackedVector3Array = _arrays(type, 0)[Mesh.ARRAY_VERTEX]
		var min_y: float = verts[0].y
		var max_y: float = verts[0].y
		for vertex: Vector3 in verts:
			min_y = minf(min_y, vertex.y)
			max_y = maxf(max_y, vertex.y)
		var floor_tolerance: float = -0.75 if ETREE_TYPES.has(type) else -0.4
		assert_between(min_y, floor_tolerance, 0.1, "%s: origin у земли" % type)
		# Камешек — самый низкий предмет (~0.17 м), выше только трава и цветы.
		assert_gt(max_y, 0.12, "%s: предмет выше земли" % type)


func test_prop_meshes_deterministic() -> void:
	# Детерминизм визуала: сеед меша — от (тип, вариант), не от порядка
	# вызовов; один и тот же меш собирается одинаково.
	for type: String in ["tree_leafy", "boulder", "rock_wall", "grass_tuft", "etree_oak"]:
		var first: PackedVector3Array = _arrays(type, 2)[Mesh.ARRAY_VERTEX]
		var second: PackedVector3Array = _arrays(type, 2)[Mesh.ARRAY_VERTEX]
		assert_eq(first, second, "%s: два вызова дают равные меши" % type)
	var variants: Array = []
	for variant: int in 3:
		variants.append(_arrays("tree_spruce", variant)[Mesh.ARRAY_VERTEX])
	assert_ne(variants[0], variants[1], "варианты ели различаются")
	var etree_variants: Array = []
	for variant: int in 3:
		etree_variants.append(_arrays("etree_pine", variant)[Mesh.ARRAY_VERTEX])
	assert_ne(etree_variants[0], etree_variants[1], "варианты сосны TreeGen различаются")


func test_etree_lods_billboard_and_height() -> void:
	# П5.9, блок 4: набор TreeGen.build_set — полная модель (кора + крона),
	# два дальних уровня и «картинка» дальнего плана; уровни дешевле
	# предыдущего (меньше граней), высота — около целевой пресета.
	# Валежник (dead_log) — одиночный ствол без кроны и LOD.
	for type: String in ETREE_TYPES:
		var set: Dictionary = TreeGen.build_set(StringName(type), 0)
		var mesh: ArrayMesh = set["mesh"]
		var log: bool = type == "dead_log"
		assert_eq(
			mesh.get_surface_count(), 1 if log else 2,
			"%s: кора + крона двумя поверхностями" % type,
		)
		var lods: Array[Mesh] = set["lods"]
		var billboard: Mesh = set["billboard"]
		if log:
			assert_eq(lods.size(), 0, "валежник без уровней детализации")
			assert_null(billboard, "валежник без картинки дальнего плана")
			continue
		assert_eq(lods.size(), 2, "%s: два дальних уровня детализации" % type)
		assert_not_null(billboard, "%s: картинка дальнего плана" % type)
		var full_indices: int = (mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() \
			+ (mesh.surface_get_arrays(1)[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
		var lod1_indices: int = (lods[0].surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() \
			+ (lods[0].surface_get_arrays(1)[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
		var lod2_indices: int = (lods[1].surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() \
			+ (lods[1].surface_get_arrays(1)[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
		assert_lt(lod1_indices, full_indices, "%s: LOD1 дешевле полной модели" % type)
		assert_lt(lod2_indices, lod1_indices, "%s: LOD2 дешевле LOD1" % type)
		# Высота нормирована к пресету (листья могут чуть выступать).
		var target: float = TreeGen.PRESETS[StringName(type)]["target_height"]
		assert_between(
			mesh.get_aabb().size.y, target * 0.75, target * 1.15,
			"%s: высота около целевой (%.1f м)" % [type, target],
		)
		assert_between(
			billboard.get_aabb().size.y, target * 0.75, target * 1.15,
			"%s: высота картинки дальнего плана" % type,
		)


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
	# Каждый предмет попадает ровно в одну группу «тип:вариант» с мешем,
	# трансформом и тоном; трансформ невырожденный (масштаб > 0).
	var data: Dictionary = _island_data()
	var art := IslandArt.build(data)
	var instanced := 0
	for key: String in art.prop_groups:
		assert_true(key.contains(":"), "ключ группы «тип:вариант»: %s" % key)
		var group: PropGroup = art.prop_groups[key]
		assert_gt(group.transforms.size(), 0, "группа %s не пустая" % key)
		assert_eq(group.colors.size(), group.transforms.size(), "тон каждому предмету %s" % key)
		# Деревья TreeGen — две поверхности (кора и крона), валежник и
		# прочие предметы — одна.
		var surfaces_expected: int = 2 if key.begins_with("etree_") else 1
		assert_eq(
			group.mesh.get_surface_count(), surfaces_expected,
			"группа %s с мешем" % key,
		)
		for i: int in group.transforms.size():
			var xf: Transform3D = group.transforms[i]
			assert_gt(xf.basis.x.length(), 0.01, "%s[%d]: масштаб не нулевой" % [key, i])
			assert_gt(xf.origin.length(), 1.0, "%s[%d]: не в мировом origin" % [key, i])
		instanced += group.transforms.size()
	assert_eq(instanced, (data["props"] as Array).size(), "все предметы в группах")


func test_art_prop_data_survives_save_load() -> void:
	# Регрессия П4.5: раньше в ресурс хранился MultiMesh, но при запекании
	# headless-скриптом set_instance_transform уходил в пустой RenderingServer,
	# buffer не заполнялся — после загрузки все предметы получали нулевой
	# трансформ и становились невидимыми (лес на скриншотах был пуст).
	# Теперь группы — чистые массивы: они обязаны переживать save/load.
	var art := IslandArt.build(_island_data())
	var path := "user://test_art_roundtrip.res"
	assert_eq(ResourceSaver.save(art, path), OK, "ресурс сохранился")
	var loaded := load(path) as IslandArt
	assert_not_null(loaded, "ресурс загрузился как IslandArt")
	assert_eq(loaded.prop_groups.size(), art.prop_groups.size(), "групп столько же")
	var trees := 0
	var in_forest := 0
	for key: String in loaded.prop_groups:
		var group: PropGroup = loaded.prop_groups[key]
		assert_eq(
			group.transforms.size(), (art.prop_groups[key] as PropGroup).transforms.size(),
			"трансформы группы %s пережили save/load" % key,
		)
		assert_eq(group.colors.size(), group.transforms.size(), "тоны %s пережили save/load" % key)
		assert_not_null(group.mesh, "меш группы %s на месте" % key)
		# П5.9, блок 4: уровни детализации и картинка дальнего плана
		# переживают save/load вместе с деревьями.
		if String(key).begins_with("etree_"):
			assert_eq(
				group.lods.size(), 2,
				"уровни детализации %s пережили save/load" % key,
			)
			assert_not_null(group.billboard, "картинка %s пережила save/load" % key)
		# П5.7, блок 2 → П5.9, блок 4: деревья Леса — процедурные «etree_*»,
		# луга и рощи — прежние «tree_*»; считаются все (включая гиганта).
		if String(key).contains("tree"):
			for xf: Transform3D in group.transforms:
				trees += 1
				if Vector2(xf.origin.x, xf.origin.z).distance_to(Vector2(-52, -52)) < 40.0:
					in_forest += 1
	assert_gt(trees, 150, "деревьев в ресурсе больше 150 (факт %d)" % trees)
	assert_gt(in_forest, 100, "лес не пуст после загрузки (в круге %d)" % in_forest)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


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
	var trail_steps := 0
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
				else:
					for lookout: Vector2i in IslandGen.LOOKOUTS:
						if Vector2(pos.x, pos.z).distance_to(lookout) <= 4.0:
							trail_steps += 1
			"pier_post":
				if pos.z >= IslandGen.CREVASSE_Z0 and pos.z <= IslandGen.CREVASSE_Z1:
					posts += 1
	assert_gt(walls, 30, "стены расщелины — предметы rock_wall")
	assert_eq(
		lookout_walls, IslandGen.LOOKOUTS.size() * 3,
		"по три стены на смотровой (север — разрыв под тропу, раздел 9.3)",
	)
	assert_between(decks, 10, 24, "настилы двух мостков через каньон")
	assert_eq(
		trail_steps, IslandGen.LOOKOUTS.size() * 11,
		"тропа на смотровую: 10 ступеней дуги и входная (раздел 9.3)",
	)
	assert_between(posts, 4, 8, "опоры мостков под настилом")
