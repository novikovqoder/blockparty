# Деревья Леса, сгенерированные самим EZ-Tree (github.com/dgreenheck/ez-tree,
# MIT, © Dan Greenheck). Конвейер: ~/eztree_gen/generate_trees.mjs гонит
# пресеты библиотеки (Pine/Oak/Aspen/Ash/Bush, вариации по seed, детали LOD —
# Tree.defaultLODLevels) через GLTFExporter в GLB; сюда попадают только
# используемые файлы (assets/visual/trees/models/, параметры — manifest.json).
# Здесь GLB читаются при запекании острова (IslandArt.build): обе поверхности
# (кора + листва) нормируются к целевой высоте вида и склеиваются в один
# ArrayMesh с материалами-шейдерами (bark_tex/canopy) — в рантайме остров
# рендерит готовые меши без загрузки GLB.
#
# Ветер листвы — формула ez-tree (#createLeafMaterial): смещение UV.y
# (черешок→кончик) с фазой из 3D-симплекс-шума; ветви, как в демо, стоят.
class_name EzTreeMeshes
extends RefCounted

const CANOPY_SHADER: Shader = preload("res://assets/shaders/canopy.gdshader")
const BARK_SHADER: Shader = preload("res://assets/shaders/tree_bark.gdshader")

## GLB и manifest — в models/ под .gdignore (как наборы kenney): импортёр
## их не трогает, в экспорт они не попадают — в рантайме меши уже запечены
## в island_art.res; читаются только при запекании и в тестах.
const DIR: String = "res://assets/visual/trees/models/"

## Кора — CC0 ambientcg (в project с П5.9; пресеты ez-tree используют
## именно Bark001–003). UV.x (обороты вокруг ствола) уже запечены
## генератором; uv_scale.y — repeat.y = 1/textureScale.y пресета.
## П17 п.2: с цветом подключены нормали и шероховатость (тот же uv).
## У Bark001 сет «1K» — 512×1024 (ниже планки аудита П5.9, как у цвета) —
## нормали/шероховатость берутся 2K; у Bark002–003 сет «1K» полный 1024.
const BARK: Dictionary = {
	"Bark001": preload(
		"res://assets/third_party/ambientcg.com/Bark001/Bark001_2K-JPG_Color.jpg"),
	"Bark002": preload(
		"res://assets/third_party/ambientcg.com/Bark002/Bark002_1K-JPG_Color.jpg"),
	"Bark003": preload(
		"res://assets/third_party/ambientcg.com/Bark003/Bark003_1K-JPG_Color.jpg"),
}
const BARK_NORMAL: Dictionary = {
	"Bark001": preload(
		"res://assets/third_party/ambientcg.com/Bark001/Bark001_2K-JPG_NormalGL.jpg"),
	"Bark002": preload(
		"res://assets/third_party/ambientcg.com/Bark002/Bark002_1K-JPG_NormalGL.jpg"),
	"Bark003": preload(
		"res://assets/third_party/ambientcg.com/Bark003/Bark003_1K-JPG_NormalGL.jpg"),
}
const BARK_ROUGHNESS: Dictionary = {
	"Bark001": preload(
		"res://assets/third_party/ambientcg.com/Bark001/Bark001_2K-JPG_Roughness.jpg"),
	"Bark002": preload(
		"res://assets/third_party/ambientcg.com/Bark002/Bark002_1K-JPG_Roughness.jpg"),
	"Bark003": preload(
		"res://assets/third_party/ambientcg.com/Bark003/Bark003_1K-JPG_Roughness.jpg"),
}

## П17 п.2 «Объём кроны» (П18 Сборка 1 п.1 — нормали больше не трогаем):
## в COLOR.rgb печётся AO по глубине внутри кроны (canopy.gdshader
## умножает albedo на COLOR.rgb). Нормали листвы — «круглые» roundedNormals
## самого генератора ez-tree (normal = направление листа + вершина от
## центра листа; options.js default true) приходят прямо из GLB, П18
## снял прежнюю подмену сферическими от центра кроны. Сдвиг центра AO к
## верхушке — там листва гуще. Запекается на всех трёх LOD; тест
## test_canopy_bake сверяет AO и нормали-из-GLB через crown_center().
const CROWN_UP_BIAS: float = 0.1
const CROWN_AO_DEPTH: float = 0.45

## Листва — PNG из репозитория ez-tree (MIT, bundled with the demo app);
## материал берёт их пересобранные версии с мипами, сохраняющими плотность
## выреза (tools/make_leaf_mips.gd, П17 п.1): движковый бокс-фильтр
## усреднял альфу карточек, и крона вдали редела («таяние»). Исходные PNG
## остаются в репозитории — из них тулa пересобирает .res.
const LEAVES: Dictionary = {
	"oak": preload("res://assets/visual/trees/leaves/oak_mips.res"),
	"aspen": preload("res://assets/visual/trees/leaves/aspen_mips.res"),
	"ash": preload("res://assets/visual/trees/leaves/ash_mips.res"),
}

## Тип предмета острова → ассеты [база GLB, целевая высота, м]. Вариант
## предмета индексирует список по модулю — IslandGen просит столько
## вариантов, сколько здесь записей.
## П18-фикс 3 «ели убрать»: высокие деревья острова — только лиственные.
## Имя ключа etree_pine НЕ переименовано: строка типа входит в данные
## расстановки и хеш острова (941246210) — позиции, варианты и коллизии
## неприкосновенны, меняется только вид. Высоты слотов прежние, 13–26 м;
## варианты догенерированы в ~/eztree_gen (Oak/Ash/Aspen Large и Medium).
## Хвойный куст Bush 3 (листва pine) заменён третьим вариантом Bush 1 —
## хвои на острове нет вовсе; pine-текстура листвы удалена из проекта.
const ASSETS: Dictionary = {
	&"etree_pine": [
		["oak_large_v2", 26.0], ["ash_large_v0", 25.0],
		["aspen_large_v0", 19.0], ["oak_medium_v2", 18.0],
		["ash_medium_v2", 13.0],
	],
	&"etree_oak": [
		["oak_medium_v0", 17.0], ["oak_medium_v1", 16.0],
		["oak_large_v0", 24.0], ["ash_medium_v0", 18.0], ["ash_medium_v1", 17.0],
	],
	&"etree_aspen": [
		["aspen_medium_v0", 16.0], ["aspen_medium_v1", 15.0],
		["aspen_small_v0", 9.0], ["aspen_small_v1", 8.5],
	],
	&"etree_bush": [
		["bush_1_v0", 2.8], ["bush_1_v1", 2.9], ["bush_2_v0", 3.0],
		["bush_2_v1", 3.1], ["bush_1_v2", 2.2],
	],
	&"etree_giant": [
		["oak_large_v1", 30.0],
	],
}

static var _manifest: Dictionary = {}
static var _cache: Dictionary = {}


## Тип — дерево ez-tree (у таких групп есть дальние уровни детализации).
static func is_tree(type: StringName) -> bool:
	return ASSETS.has(type)


## Запись манифеста генератора по базе GLB (кора, листва, AABB).
static func entry(base: String) -> Dictionary:
	if _manifest.is_empty():
		var text := FileAccess.get_file_as_string(DIR + "manifest.json")
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Array:
			for item: Dictionary in parsed:
				_manifest[String(item["name"])] = item
	if not _manifest.has(base):
		push_error("Нет %s в manifest.json деревьев ez-tree" % base)
		return {}
	return _manifest[base]


## Меши уровней детализации дерева: {"mesh": ближний уровень — гибрид
## П18 Сборки 1 п.3 (полная листва LOD0 + ветки LOD1 демо), "lods":
## [LOD1, LOD2]} — дальние уровни как LOD демо (details
## Tree.defaultLODLevels), нормированные к целевой высоте; материалы
## запечены в поверхности.
static func build_set(type: StringName, variant: int) -> Dictionary:
	var list: Array = ASSETS.get(type, [])
	if list.is_empty():
		push_error("Неизвестный тип дерева ez-tree: %s" % type)
		return {"mesh": ArrayMesh.new(), "lods": [] as Array[Mesh]}
	var base := String(list[variant % list.size()][0])
	var target_h: float = list[variant % list.size()][1]
	var key := "%s:%d" % [base, int(target_h * 100.0)]
	if _cache.has(key):
		return _cache[key]

	var info := entry(base)
	# AABB в манифесте — массивы [x, y, z]; высота GLB — по верхней точке
	# (низ ствола у ez-tree в нуле).
	var max_v: Array = info.get("lods", [{}])[0].get(
		"aabb", {}).get("max", [0.0, target_h, 0.0])
	var raw_h: float = float(max_v[1]) if max_v.size() >= 2 else target_h
	var k: float = target_h / maxf(raw_h, 0.01)
	var set := {
		"mesh": _hybrid_mesh(base, k, info),
		"lods": [
			_lod_mesh(base, 1, k, info),
			_lod_mesh(base, 2, k, info),
		] as Array[Mesh],
	}
	_cache[key] = set
	return set


## Набор уровней лаборатории ezTree (П18-ЛАБОРАТОРИЯ): тот же состав, что
## у build_set (гибрид + LOD1 + LOD2 демо), но масштаб — произвольный k
## вместо целевой высоты вида: лаборатория — копия демо-сцены, деревья
## стоят «натурального» размера генератора (демо-единицы × k), а не
## нормированные высоты острова. Запекание острова эти вызовы не трогают.
static func build_lab_set(base: String, k: float) -> Dictionary:
	var key := "%s:lab%d" % [base, int(k * 1000.0)]
	if _cache.has(key):
		return _cache[key]
	var info := entry(base)
	var set := {
		"mesh": _hybrid_mesh(base, k, info),
		"lods": [
			_lod_mesh(base, 1, k, info),
			_lod_mesh(base, 2, k, info),
		] as Array[Mesh],
	}
	_cache[key] = set
	return set


## Ближний уровень (П18 Сборка 1 п.3 «LOD умнее демо»): листва — целиком
## LOD0 (leafStride 1 — «листва НЕ трогается»), ветки — LOD1 демо
## (sectionStride 3, segmentFactor 0.75 ≈ 2/3 треугольников; прорехи
## скрыты листвой). Ветки гибрида и уровня LOD1 совпадают — стык 0↔1 при
## перетекании уровней бесшовный. Полный меш веток LOD0 (дороже всех)
## больше не читается вовсе.
static func _hybrid_mesh(base: String, k: float, info: Dictionary) -> ArrayMesh:
	var branches := _glb_surface(base, 1, "Branches")
	var leaves := _glb_surface(base, 0, "Leaves")
	var bark: Dictionary = info.get("bark", {})
	var leaf: Dictionary = info.get("leaves", {})
	var mesh := ArrayMesh.new()
	if branches != null:
		mesh.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES, _scaled(branches, k, true))
		mesh.surface_set_material(0, _bark_material(bark))
	if leaves != null:
		var leaf_arrays := _scaled(leaves, k)
		_bake_crown(leaf_arrays)
		mesh.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES, leaf_arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1,
			_canopy_material(leaf, k))
	return mesh


## Один уровень: GLB → две поверхности в один ArrayMesh, вершины ×k,
## материалы коры и листвы (шейдеры, параметры пресета из манифеста).
## GLB читается GLTFDocument'ом в обход системы импорта: те же файлы
## грузятся и при headless-запекании, и из экспортированной сборки
## (GLB без .import уходит в пакет целиком).
static func _lod_mesh(base: String, lod: int, k: float, info: Dictionary) -> ArrayMesh:
	var branches := _glb_surface(base, lod, "Branches")
	var leaves := _glb_surface(base, lod, "Leaves")
	var bark: Dictionary = info.get("bark", {})
	var leaf: Dictionary = info.get("leaves", {})
	var mesh := ArrayMesh.new()
	if branches != null:
		mesh.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES, _scaled(branches, k, true))
		mesh.surface_set_material(0, _bark_material(bark))
	if leaves != null:
		var leaf_arrays := _scaled(leaves, k)
		_bake_crown(leaf_arrays)
		mesh.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES, leaf_arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1,
			_canopy_material(leaf, k))
	return mesh


## Меш узла GLB уровня по имени (экспорт ez-tree: Tree_LOD{n} →
## Branches/Leaves); null, если файла нет или узла в нём нет.
static func _glb_surface(base: String, lod: int, node_name: String) -> Mesh:
	var path := "%s%s_lod%d.glb" % [DIR, base, lod]
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_error("Не читается GLB дерева: %s" % path)
		return null
	var scene := doc.generate_scene(state)
	var mesh := _find_mesh(scene, node_name)
	scene.free()
	return mesh


## Центр кроны для сферических нормалей и AO: центр AABB поверхности
## листвы, приподнятый к верхушке (там листва гуще) на долю CROWN_UP_BIAS
## высоты кроны.
static func crown_center(aabb: AABB) -> Vector3:
	return aabb.get_center() + Vector3(
		0.0, aabb.size.y * CROWN_UP_BIAS, 0.0)


## П17 п.2 (П18 — только AO): перепечь цвет вершин листвы под объём
## кроны — COLOR = AO: у поверхности кроны 1, к середине затемнение до
## CROWN_AO_DEPTH (глубина — эллипсоид AABB: длина (vertex − центр)/
## полуразмеры, ограничена 1). Нормали не перезаписываются — в GLB уже
## лежат «круглые» roundedNormals генератора ez-tree (options.js default
## true), П18 п.1 вернул их вместо сферических от центра кроны.
## Собственных цветов у карточек ez-tree нет — массив COLOR создаётся
## здесь.
static func _bake_crown(arrays: Array) -> void:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var aabb := AABB(verts[0], Vector3.ZERO)
	for vertex: Vector3 in verts:
		aabb = aabb.expand(vertex)
	var center := crown_center(aabb)
	var half := aabb.size * 0.5
	half = Vector3(
		maxf(half.x, 0.01), maxf(half.y, 0.01), maxf(half.z, 0.01))
	var colors := PackedColorArray()
	colors.resize(verts.size())
	for i: int in verts.size():
		var rel: Vector3 = verts[i] - center
		var depth: float = 1.0 - clampf(
			(rel / half).length(), 0.0, 1.0)
		var ao: float = 1.0 - CROWN_AO_DEPTH * depth
		colors[i] = Color(ao, ao, ao)
	arrays[Mesh.ARRAY_COLOR] = colors


## Меш узла по имени (экспорт ez-tree: Tree_LOD{n} → Branches/Leaves).
static func _find_mesh(root: Node, name: String) -> Mesh:
	var node := root.get_node_or_null(NodePath(name))
	if node == null:
		node = _find_child_by_name(root, name)
	if node is MeshInstance3D:
		return (node as MeshInstance3D).mesh
	return null


static func _find_child_by_name(node: Node, name: String) -> Node:
	for child: Node in node.get_children():
		if child.name == name:
			return child
		var found := _find_child_by_name(child, name)
		if found != null:
			return found
	return null


## Массивы вершин поверхности меша (у исходных мешей ez-tree она одна),
## умноженные на k — равномерная нормировка сохраняет нормали и UV.
## tangents — построить касательный базис коры (П18-фикс 1): ez-tree
## тангенты не экспортирует (их считает three.js), а кора с П17 читает
## NORMAL_MAP шейдера — без базиса карта нормалей ломала освещение,
## стволы и ветки светились белым. SurfaceTool строит тангенты по
## нормалям и UV поверхности.
static func _scaled(source: Mesh, k: float, tangents: bool = false) -> Array:
	var arrays: Array = source.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i: int in verts.size():
		verts[i] *= k
	arrays[Mesh.ARRAY_VERTEX] = verts
	if tangents:
		var tool := SurfaceTool.new()
		tool.create_from_arrays(arrays, Mesh.PRIMITIVE_TRIANGLES)
		tool.generate_tangents()
		arrays = tool.commit_to_arrays()
	return arrays


## Кора: текстура ambientcg по типу пресета (П17 п.2 — с нормалями и
## шероховатостью), вертикальная плотность — repeat.y = 1/textureScale.y
## (три.js #createBarkMaterial); карты лежат с тем же uv_scale.
static func _bark_material(bark: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = BARK_SHADER
	var kind := String(bark.get("type", "Bark002"))
	material.set_shader_parameter(
		"bark_tex", BARK.get(kind, BARK["Bark002"]))
	material.set_shader_parameter(
		"normal_tex", BARK_NORMAL.get(kind, BARK_NORMAL["Bark002"]))
	material.set_shader_parameter(
		"roughness_tex",
		BARK_ROUGHNESS.get(kind, BARK_ROUGHNESS["Bark002"]))
	var scale: Dictionary = bark.get("textureScale", {"x": 1.0, "y": 1.0})
	material.set_shader_parameter(
		"uv_scale", Vector2(1.0, 1.0 / maxf(float(scale.get("y", 1.0)), 0.01)))
	return material


## Листва: текстура вида, тон и порог выреза — пресет; ветер — формула
## ez-tree, амплитуда и масштаб шума нормированы (k — множитель GLB→метры).
static func _canopy_material(leaf: Dictionary, k: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CANOPY_SHADER
	material.set_shader_parameter(
		"leaf_tex", LEAVES.get(String(leaf.get("type", "oak")), LEAVES["oak"]))
	var tint: int = int(leaf.get("tint", 16777215))
	material.set_shader_parameter("leaf_tint", Color().from_rgba8(
		(tint >> 16) & 0xff, (tint >> 8) & 0xff, tint & 0xff))
	material.set_shader_parameter("alpha_cut", float(leaf.get("alphaTest", 0.5)))
	material.set_shader_parameter("wind_strength", 0.5 * k)
	material.set_shader_parameter("wind_freq", 0.5)
	material.set_shader_parameter("wind_noise_scale", 70.0 * k)
	return material
