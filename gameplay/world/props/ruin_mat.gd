# Фабрика материалов камня руин (доработка-2 П5.13, П4): стены, башни,
# колонны, арки, ворота и каменные стены расщелины — ShaderMaterial на
# ruin_masonry.gdshader (текстуры CC0: кладка polyhaven old_stone_wall_02,
# мох ambientCG Moss001; трипланар по мировой позиции — швы кладки
# непрерывны через блоки). Вершинные цвета мешей остаются тонировкой
# деталей. Кэшируется по типу: материал один на все экземпляры MultiMesh.
# В headless (серверные прогоны без рендера) шейдеры не компилируются —
# плоский StandardMaterial3D с вершинным цветом, логика не зависит.
class_name RuinMat
extends RefCounted

const SHADER: Shader = preload("res://assets/shaders/ruin_masonry.gdshader")
const PAL: Palette = preload("res://assets/palette.tres")
const MASONRY_TEX: Texture2D = preload(
	"res://assets/third_party/polyhaven.com/old_stone_wall_02/old_stone_wall_02_diffuse_2k.jpg")
const MASONRY_NORMAL: Texture2D = preload(
	"res://assets/third_party/polyhaven.com/old_stone_wall_02/old_stone_wall_02_nor_gl_2k.jpg")
const MOSS_TEX: Texture2D = preload(
	"res://assets/third_party/ambientcg.com/Moss001/Moss001_1K-JPG_Color.jpg")

static var _cache: Dictionary = {}


## Тип обрабатывается этой фабрикой (IslandView._build_props): вся кладка
## острова — руины и каменные стены расщелины/смотровых.
static func handles(type: StringName) -> bool:
	return ["ruin_block", "ruin_tower", "ruin_gate", "ruin_column",
		"ruin_arch", "rock_wall"].has(String(type))


## Материал типа: кладка одна, типы отличаются густотой мха и тоном
## (колонны чуть светлее — вытесаны, стены у воды замшелее).
static func for_type(type: StringName) -> Material:
	if WorldMaterials.want_flat():
		return _flat()
	if _cache.has(type):
		return _cache[type]
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("masonry_tex", MASONRY_TEX)
	material.set_shader_parameter("masonry_normal", MASONRY_NORMAL)
	material.set_shader_parameter("moss_tex", MOSS_TEX)
	match String(type):
		"ruin_column":
			material.set_shader_parameter("tint", Vector3(1.66, 1.72, 1.82))
			material.set_shader_parameter("moss_amount", 0.3)
		"ruin_tower":
			material.set_shader_parameter("tint", Vector3(1.48, 1.56, 1.66))
			material.set_shader_parameter("moss_amount", 0.45)
		"ruin_gate":
			material.set_shader_parameter("tint", Vector3(1.6, 1.66, 1.76))
			material.set_shader_parameter("moss_amount", 0.5)
		"rock_wall":
			# Стены расщелины и смотровых — в сырой низине, мха больше.
			material.set_shader_parameter("tint", Vector3(1.42, 1.5, 1.6))
			material.set_shader_parameter("moss_amount", 0.8)
		_:
			material.set_shader_parameter("tint", Vector3(1.55, 1.62, 1.72))
			material.set_shader_parameter("moss_amount", 0.65)
	_cache[type] = material
	return material


## Материал плиты ворот (RuinGate) и постаментов плит: та же кладка,
## темнее и почти без мха — притолока вытерлась руками, плиты ходят
## в гнёздах. Отдельная запись кэша: узел ворот не из MultiMesh.
static func panel() -> Material:
	if WorldMaterials.want_flat():
		return _flat()
	if _cache.has("panel"):
		return _cache["panel"]
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("masonry_tex", MASONRY_TEX)
	material.set_shader_parameter("masonry_normal", MASONRY_NORMAL)
	material.set_shader_parameter("moss_tex", MOSS_TEX)
	# Плита — BoxMesh без вершинных цветов (белые): множитель ниже
	# единицы даёт тёмный камень, как прежний ruin_dark.
	material.set_shader_parameter("tint", Vector3(0.66, 0.7, 0.78))
	material.set_shader_parameter("moss_amount", 0.12)
	_cache["panel"] = material
	return material


## Материал каменного постамента плит (RuinPlate): кладка темнее стен,
## без мха — рабочий камень у тропы. BaseMaterial3D с текстурой: плит
## три, материал локальный (эмиссия нажатия переключается у каждого).
static func plate_stone() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	if WorldMaterials.want_flat():
		material.albedo_color = PAL.ruin_dark.darkened(0.1)
		return material
	material.albedo_texture = MASONRY_TEX
	material.albedo_color = Color(0.62, 0.64, 0.68)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.uv1_scale = Vector3(0.6, 0.25, 0.6)
	material.roughness = 0.9
	return material


## Headless-вариант (dummy-рендер): плоский вершинный цвет без шейдера.
static func _flat() -> Material:
	var flat := StandardMaterial3D.new()
	flat.vertex_color_use_as_albedo = true
	return flat
