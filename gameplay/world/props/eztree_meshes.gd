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
const BARK: Dictionary = {
	"Bark001": preload(
		"res://assets/third_party/ambientcg.com/Bark001/Bark001_2K-JPG_Color.jpg"),
	"Bark002": preload(
		"res://assets/third_party/ambientcg.com/Bark002/Bark002_1K-JPG_Color.jpg"),
	"Bark003": preload(
		"res://assets/third_party/ambientcg.com/Bark003/Bark003_1K-JPG_Color.jpg"),
}

## Листва — PNG из репозитория ez-tree (MIT, bundled with the demo app).
const LEAVES: Dictionary = {
	"pine": preload("res://assets/visual/trees/leaves/pine.png"),
	"oak": preload("res://assets/visual/trees/leaves/oak.png"),
	"aspen": preload("res://assets/visual/trees/leaves/aspen.png"),
	"ash": preload("res://assets/visual/trees/leaves/ash.png"),
}

## Тип предмета острова → ассеты [база GLB, целевая высота, м]. Вариант
## предмета индексирует список по модулю — IslandGen просит столько
## вариантов, сколько здесь записей.
const ASSETS: Dictionary = {
	&"etree_pine": [
		["pine_large_v0", 26.0], ["pine_large_v1", 25.0],
		["pine_medium_v0", 19.0], ["pine_medium_v1", 18.0],
		["pine_small_v0", 13.0],
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
		["bush_2_v1", 3.1], ["bush_3_v0", 2.2],
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


## Меши уровней детализации дерева: {"mesh": полная модель,
## "lods": [LOD1, LOD2]} — как LOD демо (details Tree.defaultLODLevels),
## нормированные к целевой высоте; материалы запечены в поверхности.
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
		"mesh": _lod_mesh(base, 0, k, info),
		"lods": [
			_lod_mesh(base, 1, k, info),
			_lod_mesh(base, 2, k, info),
		] as Array[Mesh],
	}
	_cache[key] = set
	return set


## Один уровень: GLB → две поверхности в один ArrayMesh, вершины ×k,
## материалы коры и листвы (шейдеры, параметры пресета из манифеста).
## GLB читается GLTFDocument'ом в обход системы импорта — как CC0-модели
## kenney (Cc0Meshes): те же файлы грузятся и при headless-запекании,
## и из экспортированной сборки (GLB без .import уходит в пакет целиком).
static func _lod_mesh(base: String, lod: int, k: float, info: Dictionary) -> ArrayMesh:
	var path := "%s%s_lod%d.glb" % [DIR, base, lod]
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_error("Не читается GLB дерева: %s" % path)
		return ArrayMesh.new()
	var scene := doc.generate_scene(state)
	var branches := _find_mesh(scene, "Branches")
	var leaves := _find_mesh(scene, "Leaves")
	scene.free()

	var bark: Dictionary = info.get("bark", {})
	var leaf: Dictionary = info.get("leaves", {})
	var mesh := ArrayMesh.new()
	if branches != null:
		mesh.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES, _scaled(branches, k))
		mesh.surface_set_material(0, _bark_material(bark))
	if leaves != null:
		mesh.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES, _scaled(leaves, k))
		mesh.surface_set_material(mesh.get_surface_count() - 1,
			_canopy_material(leaf, k))
	return mesh


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
static func _scaled(source: Mesh, k: float) -> Array:
	var arrays: Array = source.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i: int in verts.size():
		verts[i] *= k
	arrays[Mesh.ARRAY_VERTEX] = verts
	return arrays


## Кора: текстура ambientcg по типу пресета, вертикальная плотность —
## repeat.y = 1/textureScale.y (три.js #createBarkMaterial).
static func _bark_material(bark: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = BARK_SHADER
	material.set_shader_parameter(
		"bark_tex", BARK.get(String(bark.get("type", "Bark002")), BARK["Bark002"]))
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
