# CC0-модели окружения (шаг 3 П4.5; П5.7 — блок 2 добавил Poly Haven):
# наборы kenney.nl и polyhaven.com из assets/third_party (правила — CLAUDE.md,
# записи — assets/third_party/LICENSES.md). GLB/glTF читается напрямую
# GLTFDocument'ом — папки наборов закрыты .gdignore, импорт редактора не нужен
# и в экспорт игры файлы не попадают. Поверхности перекрашиваются в палитры
# игры вершинными цветами (шейдер lowpoly умножает их на instance-тон зоны —
# как у процедурных мешей PropMeshes); сканы Poly Haven берут цвет из своей
# текстуры (режим "tex"), а меш нормируется под эталонные размеры — scale
# предметов IslandGen не меняется. Используется только при запекании острова
# (tools/generate_island.gd) и в тестах: в игре меши в island_art.res.
class_name Cc0Meshes
extends RefCounted

const PAL: Palette = preload("res://assets/palette.tres")
## Корень наборов — папки сайтов в assets/third_party (CLAUDE.md). Набор
## в MODELS — путь от корня: "kenney.nl/nature-kit", "polyhaven.com/fern_02".
const ROOT: String = "res://assets/third_party/"

## Тип → [набор, файлы-варианты (порядок = variant IslandGen), целевая высота,
## целевой макс. горизонтальный размер (м), запасная категория цвета для
## материалов с безымянной поверхностью, режим цвета (необязателен:
## "tex" — цвет вершин из текстуры модели как есть, для сканов Poly Haven;
## по умолчанию — палитры игры)]. Имя файла с точкой берётся целиком
## (fern_02_2k.gltf), без — добавляется .glb (kenney). Целевые размеры —
## эталоны для нормировки, см. PROP_TYPES в тестах.
const MODELS: Dictionary = {
	&"tree_leafy": [
		"kenney.nl/nature-kit",
		["tree_default", "tree_oak", "tree_detailed", "tree_fat", "tree_small"],
		3.8, 1.7, "trunk",
	],
	&"tree_spruce": [
		"kenney.nl/nature-kit",
		["tree_pineRoundA", "tree_pineDefaultA", "tree_pineSmallA"],
		3.2, 2.1, "trunk",
	],
	# П5.9, блок 4: деревья, кусты и валежник Леса (rtree_leafy, rshrub,
	# tree_giant, rlog) больше не сканы — процедурный генератор TreeGen
	# (порт EZ-Tree), см. PropMeshes.mesh. Сканы Poly Haven удалены.
	&"rrock": [
		"",
		[
			"polyhaven.com/rock_07/rock_07_lo.res",
			"polyhaven.com/rock_09/rock_09_lo.res",
			"polyhaven.com/boulder_01/boulder_01_lo.res",
		],
		0.6, 1.0, "stone",
	],
	# П5.9, блок 3: rgrass и fern больше не сканы — процедурные меши
	# ForestPlants (материал ForestMat), см. PropMeshes.mesh.
	&"bush": [
		"kenney.nl/nature-kit",
		["plant_bush", "plant_bushSmall", "plant_bushDetailed"],
		0.8, 1.2, "leaf",
	],
	&"grass_tuft": [
		"kenney.nl/nature-kit",
		["grass", "grass_leafs", "grass_large"],
		0.5, 0.45, "leaf",
	],
	&"flower": [
		"kenney.nl/nature-kit",
		["flower_redA", "flower_yellowA", "flower_purpleA"],
		0.35, 0.35, "leaf",
	],
	&"boulder": [
		"kenney.nl/nature-kit",
		["rock_largeA", "rock_largeB", "rock_largeD"],
		0.95, 1.15, "stone",
	],
	&"rock_pillar": [
		"kenney.nl/nature-kit",
		["rock_tallA", "rock_tallB", "rock_tallC"],
		2.4, 1.3, "stone",
	],
	&"pebble": [
		"kenney.nl/nature-kit",
		["rock_smallA", "rock_smallB", "rock_smallC"],
		0.18, 0.32, "stone",
	],
	&"reed": [
		"kenney.nl/nature-kit",
		["plant_flatTall", "plant_flatShort"],
		0.55, 0.4, "leaf",
	],
	&"bench": [
		"kenney.nl/nature-kit",
		["log", "log_large"],
		0.5, 2.0, "trunk",
	],
	&"ruin_column": [
		"kenney.nl/castle-kit",
		["wall-pillar"],
		1.55, 1.05, "stone",
	],
	&"ruin_arch": [
		"kenney.nl/castle-kit",
		["tower-square-arch"],
		2.7, 2.3, "stone",
	],
}

static var _cache: Dictionary = {}


## Меш CC0-модели (null — тип процедурный, путь PropMeshes). Вариант берётся
## по модулю числа файлов: IslandGen просит 3–5 вариантов на тип.
static func mesh(type: StringName, variant: int) -> ArrayMesh:
	if not MODELS.has(type):
		return null
	var cfg: Array = MODELS[type]
	var files: PackedStringArray = cfg[1]
	var index: int = variant % files.size()
	var key: String = "%s:%d" % [type, index]
	if _cache.has(key):
		return _cache[key]
	var file := files[index]
	if not file.contains("."):
		file += ".glb"
	var path := ROOT.path_join(String(cfg[0])).path_join(file)
	var mesh := _build_res(path, cfg) if file.ends_with(".res") \
		else _build(path, cfg)
	_cache[key] = mesh
	return mesh


## Прочитать GLB и собрать один перекрашенный нормированный ArrayMesh.
static func _build(path: String, cfg: Array) -> ArrayMesh:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_error("CC0-модель не читается: " + path)
		return ArrayMesh.new()
	var root := doc.generate_scene(state)
	var parts: Array = []
	var color_mode := "palette"
	if cfg.size() > 5:
		color_mode = String(cfg[5])
	_collect(root, Transform3D.IDENTITY, String(cfg[4]), color_mode, parts)
	root.free()
	if parts.is_empty():
		push_error("CC0-модель без треугольных поверхностей: " + path)
		return ArrayMesh.new()
	return _normalized(parts, float(cfg[2]), float(cfg[3]))


## Децимированный скан Poly Haven (tools/decimate_polyhaven.gd): .res уже
## несёт цвет в вершинах и общий базис — читаем поверхности как «детали»
## и только нормируем под эталонные размеры.
static func _build_res(path: String, cfg: Array) -> ArrayMesh:
	var mesh: Mesh = load(path)
	if mesh == null or mesh.get_surface_count() == 0:
		push_error("CC0 .res не читается: " + path)
		return ArrayMesh.new()
	var parts: Array = []
	for surface: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		if arrays.is_empty() \
				or (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			continue
		parts.append({
			"verts": arrays[Mesh.ARRAY_VERTEX],
			"colors": arrays[Mesh.ARRAY_COLOR],
			"indices": arrays[Mesh.ARRAY_INDEX],
		})
	if parts.is_empty():
		push_error("CC0 .res без поверхностей: " + path)
		return ArrayMesh.new()
	return _normalized(parts, float(cfg[2]), float(cfg[3]))


## Обход узлов с накоплением трансформа; каждая поверхность — «деталь»
## с вершинами, перекрашенными в палитры игры, и индексами.
static func _collect(
	node: Node3D, parent_xf: Transform3D, fallback: String,
	color_mode: String, parts: Array
) -> void:
	var xf := parent_xf * node.transform
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh != null:
			for surface: int in mesh.get_surface_count():
				var arrays: Array = mesh.surface_get_arrays(surface)
				if arrays.is_empty() or mesh.surface_get_primitive_type(surface) \
						!= Mesh.PRIMITIVE_TRIANGLES:
					continue
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				if verts.is_empty():
					continue
				var colors := PackedColorArray()
				colors.resize(verts.size())
				var material: Material = mesh.surface_get_material(surface)
				var flat: StandardMaterial3D = material as StandardMaterial3D
				var source := PackedFloat32Array()
				if arrays[Mesh.ARRAY_COLOR] is PackedFloat32Array:
					source = arrays[Mesh.ARRAY_COLOR]
				var textured := flat != null and flat.albedo_texture != null
				if source.size() == verts.size() * 4:
					# Цвет в вершинах: палитра руин по яркости исходного цвета
					# — тёмные швы и светлые камни кладки сохраняются.
					for i: int in verts.size():
						var brightness := clampf(
							maxf(
								source[i * 4],
								maxf(source[i * 4 + 1], source[i * 4 + 2]),
							),
							0.0, 1.0,
						)
						colors[i] = PAL.ruin_dark.lerp(
							PAL.ruin_brick, brightness
						)
				elif textured:
					# Цвет в текстуре: сэмпл по UV каждой вершины. Сканы
					# Poly Haven (color_mode "tex") берут цвет пикселя как
					# есть (sRGB → линейный), атлас castle-kit — палитру руин
					# по яркости: кладка и грани остаются разными.
					var image: Image = flat.albedo_texture.get_image()
					var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
					for i: int in verts.size():
						var pixel := image.get_pixel(
							clampi(roundi(uv[i].x * image.get_width()), 0,
								image.get_width() - 1),
							clampi(roundi((1.0 - uv[i].y) * image.get_height()),
								0, image.get_height() - 1),
						)
						if color_mode == "tex":
							colors[i] = pixel.srgb_to_linear()
							continue
						var brightness := clampf(
							maxf(pixel.r, maxf(pixel.g, pixel.b)), 0.0, 1.0
						)
						colors[i] = PAL.ruin_dark.lerp(
							PAL.ruin_brick, brightness
						)
				else:
					# Цвет в материале (nature-kit) или материала нет вовсе:
					# категория по имени, последняя надежда — запасной цвет.
					colors.fill(_surface_color(material, fallback))
				for i: int in verts.size():
					verts[i] = xf * verts[i]
				parts.append({
					"verts": verts,
					"colors": colors,
					"indices": arrays[Mesh.ARRAY_INDEX],
				})
	for child: Node in node.get_children():
		if child is Node3D:
			_collect(child as Node3D, xf, fallback, color_mode, parts)


## Цвет поверхности nature-kit по имени материала kenney (в GLB имена
## стабильны: woodBark, leafsGreen, grass, dirt, colorRed...). Лепестки
## (color*) красятся белыми — оттенок даёт instance-тон из палитры flowers.
static func _surface_color(material: Material, fallback: String) -> Color:
	var name := ""
	if material is StandardMaterial3D:
		name = (material as StandardMaterial3D).resource_name
	match name:
		"woodBark", "woodBarkDark":
			return PAL.trunk
		"woodInner":
			return PAL.planks
		"leafsGreen", "leafsDark":
			return PAL.zone_leaf[1]
		"grass":
			return PAL.grass
		"dirt":
			return PAL.stone
	if name.begins_with("color"):
		return Color.WHITE
	return _fallback_color(fallback)


## Запасной цвет для безымянных поверхностей (по категории типа предмета).
static func _fallback_color(fallback: String) -> Color:
	match fallback:
		"trunk":
			return PAL.trunk
		"leaf":
			return PAL.zone_leaf[1]
	return PAL.stone


## Нормировка под эталонные размеры (меньший из коэффициентов по высоте и
## горизонтали) со сдвигом «ноги на землю»: origin меша — у основания,
## как у процедурных моделей PropMeshes.
static func _normalized(parts: Array, height: float, width: float) -> ArrayMesh:
	var min_v := Vector3(INF, INF, INF)
	var max_v := Vector3(-INF, -INF, -INF)
	for part: Dictionary in parts:
		for v: Vector3 in part["verts"]:
			min_v = min_v.min(v)
			max_v = max_v.max(v)
	var size := max_v - min_v
	var scale := minf(
		height / maxf(size.y, 0.001),
		width / maxf(maxf(size.x, size.z), 0.001),
	)
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for part: Dictionary in parts:
		var base: int = verts.size()
		for v: Vector3 in part["verts"]:
			verts.append(Vector3(
				v.x * scale, (v.y - min_v.y) * scale, v.z * scale
			))
		colors.append_array(part["colors"])
		for index: int in part["indices"]:
			indices.append(base + index)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
