# Фабрика материалов дерева настилов (доработка-2 П5.13, П5): причал
# (настил, сваи, кнехты) и ступени лестниц смотровых — ShaderMaterial на
# planks_wood.gdshader, текстура плах ambientCG Planks007 (CC0),
# трипланар по мировой позиции. Вершинные цвета мешей тонируют доски.
# Кэшируется по типу: материал один на все экземпляры MultiMesh.
# В headless (без рендера) — плоский StandardMaterial3D с вершинным
# цветом, логика игры от рендера не зависит.
class_name WoodMat
extends RefCounted

const SHADER: Shader = preload("res://assets/shaders/planks_wood.gdshader")
const WOOD_TEX: Texture2D = preload(
	"res://assets/third_party/ambientcg.com/Planks007/Planks007_2K-JPG_Color.jpg")
const WOOD_NORMAL: Texture2D = preload(
	"res://assets/third_party/ambientcg.com/Planks007/Planks007_2K-JPG_NormalGL.jpg")

static var _cache: Dictionary = {}


## Тип обрабатывается этой фабрикой (IslandView._build_props): дерево
## настилов у воды — причал и мостки.
static func handles(type: StringName) -> bool:
	return ["plank_deck", "pier_post"].has(String(type))


## Материал типа: настил — тёплые плахи; сваи и кнехты темнее и с
## мельчайшим тайлом (крупные кольца на столбе читаются бревном).
static func for_type(type: StringName) -> Material:
	if WorldMaterials.want_flat():
		return _flat()
	if _cache.has(type):
		return _cache[type]
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("wood_tex", WOOD_TEX)
	material.set_shader_parameter("wood_normal", WOOD_NORMAL)
	if String(type) == "pier_post":
		material.set_shader_parameter("tint", Vector3(1.02, 0.94, 0.8))
		material.set_shader_parameter("tile_m", 1.1)
	else:
		material.set_shader_parameter("tint", Vector3(1.28, 1.18, 1.02))
		material.set_shader_parameter("tile_m", 1.6)
	_cache[type] = material
	return material


## Материал ступеней лестниц смотровых (BoxMesh без вершинных цветов:
## множитель ниже единицы — доски темнее настила, «вытертые» сапогами).
static func rungs() -> Material:
	if WorldMaterials.want_flat():
		return _flat()
	if _cache.has("rungs"):
		return _cache["rungs"]
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("wood_tex", WOOD_TEX)
	material.set_shader_parameter("wood_normal", WOOD_NORMAL)
	material.set_shader_parameter("tint", Vector3(0.92, 0.84, 0.72))
	material.set_shader_parameter("tile_m", 1.4)
	_cache["rungs"] = material
	return material


## Headless-вариант (dummy-рендер): плоский вершинный цвет без шейдера.
static func _flat() -> Material:
	var flat := StandardMaterial3D.new()
	flat.vertex_color_use_as_albedo = true
	return flat
