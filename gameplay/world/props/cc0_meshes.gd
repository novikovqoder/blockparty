# CC0-модели окружения (шаг 3 П4.5): наборы kenney.nl из assets/third_party
# (правила — CLAUDE.md, записи — assets/third_party/LICENSES.md). GLB читается
# напрямую GLTFDocument'ом — папки наборов закрыты .gdignore, импорт редактора
# не нужен и в экспорт игры файлы не попадают. Поверхности перекрашиваются
# в палитры игры вершинными цветами (шейдер lowpoly умножает их на instance-тон
# зоны — как у процедурных мешей PropMeshes), а меш нормируется под эталонные
# размеры процедурной модели того же типа — scale предметов IslandGen не
# меняется. Используется только при запекании острова (tools/generate_island.gd)
# и в тестах: в игре меши уже встроены в island_art.res.
class_name Cc0Meshes
extends RefCounted

const PAL: Palette = preload("res://assets/palette.tres")
const ROOT: String = "res://assets/third_party/kenney.nl/"

## Тип → [набор, файлы-варианты (порядок = variant IslandGen), целевая высота,
## целевой макс. горизонтальный размер (м), запасная категория цвета для
## материалов с безымянной поверхностью]. Целевые размеры — эталоны
## процедурных мешей, которые эти типы заменяют (см. PROP_TYPES в тестах).
const MODELS: Dictionary = {
	&"tree_leafy": [
		"nature-kit",
		["tree_default", "tree_oak", "tree_detailed", "tree_fat", "tree_small"],
		3.8, 1.7, "trunk",
	],
	&"tree_spruce": [
		"nature-kit",
		["tree_pineRoundA", "tree_pineDefaultA", "tree_pineSmallA"],
		3.2, 2.1, "trunk",
	],
	&"bush": [
		"nature-kit",
		["plant_bush", "plant_bushSmall", "plant_bushDetailed"],
		0.8, 1.2, "leaf",
	],
	&"grass_tuft": [
		"nature-kit",
		["grass", "grass_leafs", "grass_large"],
		0.5, 0.45, "leaf",
	],
	&"flower": [
		"nature-kit",
		["flower_redA", "flower_yellowA", "flower_purpleA"],
		0.35, 0.35, "leaf",
	],
	&"boulder": [
		"nature-kit",
		["rock_largeA", "rock_largeB", "rock_largeD"],
		0.95, 1.15, "stone",
	],
	&"rock_pillar": [
		"nature-kit",
		["rock_tallA", "rock_tallB", "rock_tallC"],
		2.4, 1.3, "stone",
	],
	&"pebble": [
		"nature-kit",
		["rock_smallA", "rock_smallB", "rock_smallC"],
		0.18, 0.32, "stone",
	],
	&"reed": [
		"nature-kit",
		["plant_flatTall", "plant_flatShort"],
		0.55, 0.4, "leaf",
	],
	&"bench": [
		"nature-kit",
		["log", "log_large"],
		0.5, 2.0, "trunk",
	],
	&"ruin_column": [
		"castle-kit",
		["wall-pillar"],
		1.55, 1.05, "stone",
	],
	&"ruin_arch": [
		"castle-kit",
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
	var path: String = "%s%s/%s.glb" % [ROOT, cfg[0], files[index]]
	var mesh := _build(path, cfg)
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
	_collect(root, Transform3D.IDENTITY, String(cfg[4]), parts)
	root.free()
	if parts.is_empty():
		push_error("CC0-модель без треугольных поверхностей: " + path)
		return ArrayMesh.new()
	return _normalized(parts, float(cfg[2]), float(cfg[3]))


## Обход узлов с накоплением трансформа; каждая поверхность — «деталь»
## с вершинами, перекрашенными в палитры игры, и индексами.
static func _collect(
	node: Node3D, parent_xf: Transform3D, fallback: String, parts: Array
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
					# Цвет в текстуре (castle-kit «colormap.png»): сэмпл по UV
					# каждой вершины, палитра руин по яркости пикселя —
					# кладка и грани остаются разными.
					var image: Image = flat.albedo_texture.get_image()
					var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
					for i: int in verts.size():
						var pixel := image.get_pixel(
							clampi(roundi(uv[i].x * image.get_width()), 0,
								image.get_width() - 1),
							clampi(roundi((1.0 - uv[i].y) * image.get_height()),
								0, image.get_height() - 1),
						)
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
			_collect(child as Node3D, xf, fallback, parts)


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
