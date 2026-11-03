# Импосторы дальних деревьев (П17 п.3): quad-биллборд вместо LOD2
# (90–220 м) — теперь дальний уровень виден до 400 м, за туман. Атласы
# (albedo + нормали, 8 азимутов × 2 подъёма на базу GLB) печёт
# tools/bake_tree_impostors.gd в assets/visual/trees/impostors/; одна
# база обслуживает все варианты вида (варианты — масштаб, quad берёт
# размер из AABB полной модели группы). Материал — impostor.gdshader:
# кадр по углу «камера → дерево», свет по атласу нормалей.
class_name TreeImpostors
extends RefCounted

const SHADER: Shader = preload("res://assets/shaders/impostor.gdshader")
const DIR: String = "res://assets/visual/trees/impostors/"

## Дальняя зона импосторов: начало — стык с LOD1 (плавный дизеринг-фейд
## FADE_SELF у обоих), конец — за туманом (у юбки дна, П15-ДОП2).
const RANGE_BEGIN: float = 90.0
const RANGE_END: float = 400.0
const RANGE_MARGIN: float = 10.0
## Порог вырезки атласа (в атласе запечён контур дерева с альфой).
const ALPHA_CUT: float = 0.3
## Запас квада над AABB дерева: крона чуть выступает за ветки, в кадре
## атласа 8 % полей (тула печатала с тем же запасом).
const QUAD_PAD: float = 1.08


## Импостор-уровень группы «тип:вариант»: мультимеш квада по трансформам
## группы, материал базы варианта. Тень не отбрасывает (дальний план).
static func build(key: String, group: PropGroup) -> MultiMeshInstance3D:
	var type := key.get_slice(":", 0)
	var variant := int(key.get_slice(":", 1))
	var list: Array = EzTreeMeshes.ASSETS.get(StringName(type), [])
	if list.is_empty():
		return null
	var base := String(list[variant % list.size()][0])
	var instance := MultiMeshInstance3D.new()
	instance.name = "Props_%s_%d_impostor" % [type, variant]
	instance.multimesh = group.to_multimesh(_quad_mesh(group.mesh))
	instance.material_override = _material(base)
	instance.visibility_range_begin = RANGE_BEGIN
	instance.visibility_range_end = RANGE_END
	instance.visibility_range_begin_margin = RANGE_MARGIN
	instance.visibility_range_end_margin = RANGE_MARGIN
	instance.visibility_range_fade_mode = \
		GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


## Quad-биллборд варианта: вертикальная плоскость XY (нормаль +Z) вокруг
## оси дерева. Квад квадратный — как кадр тулы (ортокамера покрывает
## максимальную размерность AABB × QUAD_PAD, кадр 128×128): рамка квада
## совпадает с рамкой атласа, силуэт не искажается. Кадр и поворот
## к камере делает шейдер.
static func _quad_mesh(source: Mesh) -> ArrayMesh:
	var aabb := source.get_aabb()
	var spread: float = maxf(aabb.size.y, maxf(aabb.size.x, aabb.size.z))
	var side: float = spread * QUAD_PAD
	var bottom: float = aabb.get_center().y - side * 0.5
	var half := side * 0.5
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-half, bottom, 0.0),
		Vector3(half, bottom, 0.0),
		Vector3(-half, bottom + side, 0.0),
		Vector3(half, bottom + side, 0.0),
	])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(1.0, 0.0),
		Vector2(0.0, 1.0), Vector2(1.0, 1.0),
	])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([
		Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK,
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 1, 3, 2])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Материал базы: атласы albedo/нормалей и порог вырезки. Раскладка
## (4×4 кадра, 8 азимутов) — константы шейдера, тула печёт ту же.
static func _material(base: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(
		"atlas_tex", load(DIR + "%s_impostor.png" % base))
	material.set_shader_parameter(
		"normal_tex", load(DIR + "%s_impostor_normal.png" % base))
	material.set_shader_parameter("alpha_cut", ALPHA_CUT)
	return material
