# Фабрика материалов low-poly (раздел 16 SPEC): ShaderMaterial на общем
# шейдере lowpoly.gdshader, кэшируется по цвету — предметов одного цвета
# сотни, материал нужен один. Вершинные цвета меша умножаются на albedo,
# поэтому предметы с раскраской в вершинах передают Color.WHITE.
# В headless (серверные прогоны без рендера) шейдер не компилируется —
# отдаём плоский StandardMaterial3D, логика от этого не зависит.
class_name LowPolyMat
extends RefCounted

const SHADER: Shader = preload("res://assets/shaders/lowpoly.gdshader")

static var _cache: Dictionary = {}


## Материал с цветом albedo (для однотонных мешей: мобы, коллизионные столбы).
static func mat(color: Color, emission_energy: float = 0.0) -> ShaderMaterial:
	var key: String = "%s@%f" % [color.to_html(), emission_energy]
	if _cache.has(key):
		return _cache[key]
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("albedo", Color(color, 1.0))
	if emission_energy > 0.0:
		material.set_shader_parameter("emission_color", Color(color, 1.0))
		material.set_shader_parameter("emission_energy", emission_energy)
	_cache[key] = material
	return material


## Материал для мешей с вершинными цветами (рельеф, предметы): albedo белый,
## цвет берётся из COLOR (вершины × instance-цвет MultiMesh).
static func vertex() -> ShaderMaterial:
	return mat(Color.WHITE)


## Headless-вариант (dummy-рендер): плоский цвет без шейдера.
static func flat_or_vertex() -> Material:
	if DisplayServer.get_name() == "headless":
		var flat := StandardMaterial3D.new()
		flat.vertex_color_use_as_albedo = true
		return flat
	return vertex()


## Однотонный материал с цветом (мобы): в headless — плоский Standard без
## шейдера, логика и тесты от рендера не зависят.
static func flat_or_mat(color: Color, emission_energy: float = 0.0) -> Material:
	if DisplayServer.get_name() == "headless":
		var flat := StandardMaterial3D.new()
		flat.albedo_color = color
		flat.roughness = 1.0
		if emission_energy > 0.0:
			flat.emission_enabled = true
			flat.emission = color
			flat.emission_energy_multiplier = emission_energy
		return flat
	return mat(color, emission_energy)
