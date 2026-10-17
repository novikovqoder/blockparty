# Фабрика материалов растительности Леса (П5.9): трава/папоротники/цветы —
# ShaderMaterial на grass_field.gdshader (градиент, ветер, спад густоты от
# камеры), камни — rock_moss.gdshader (мох островками по всей видимой
# поверхности, гуще кверху). Цвета — из
# assets/visual_palette.tres. Кэшируется по типу: материал один на все
# экземпляры MultiMesh типа. В headless (серверные прогоны без рендера)
# шейдеры не компилируются — плоский StandardMaterial3D, логика не зависит.
class_name ForestMat
extends RefCounted

const GRASS_SHADER: Shader = preload("res://assets/shaders/grass_field.gdshader")
const ROCK_SHADER: Shader = preload("res://assets/shaders/rock_moss.gdshader")
const VPAL: VisualPalette = preload("res://assets/visual_palette.tres")

static var _cache: Dictionary = {}


## Тип обрабатывается этой фабрикой (IslandView._build_props).
static func handles(type: StringName) -> bool:
	return ["rgrass", "fern", "rflower", "riris", "mrock", "rrock"].has(String(type))


## Материал типа (трава — градиент; папоротник/цветы — цвет вершин;
## камни — мох). Амплитуда ветра у травы мелкая и частая, у вай — меньше.
static func for_type(type: StringName) -> Material:
	if DisplayServer.get_name() == "headless":
		return _flat()
	if _cache.has(type):
		return _cache[type]
	var material := ShaderMaterial.new()
	match String(type):
		"rgrass":
			material.shader = GRASS_SHADER
			material.set_shader_parameter("use_gradient", 1.0)
			material.set_shader_parameter("base_color", VPAL.grass_base)
			material.set_shader_parameter("tip_color", VPAL.grass_tip)
			# Доработка под эталон: ветер заметен волнами по поляне —
			# кончик травинки гуляет до ~15 см в порыве.
			material.set_shader_parameter("wind_amplitude", 0.11)
			material.set_shader_parameter("wind_freq", 1.8)
			material.set_shader_parameter("fade_start", 40.0)
			material.set_shader_parameter("fade_end", 58.0)
		"fern":
			material.shader = GRASS_SHADER
			material.set_shader_parameter("use_gradient", 0.0)
			material.set_shader_parameter("wind_amplitude", 0.045)
			material.set_shader_parameter("wind_freq", 1.2)
			material.set_shader_parameter("fade_start", 45.0)
			material.set_shader_parameter("fade_end", 62.0)
		"rflower":
			material.shader = GRASS_SHADER
			material.set_shader_parameter("use_gradient", 0.0)
			material.set_shader_parameter("wind_amplitude", 0.04)
			material.set_shader_parameter("wind_freq", 2.2)
			material.set_shader_parameter("fade_start", 40.0)
			material.set_shader_parameter("fade_end", 56.0)
		# Ирис выше цветка — стебель качается шире, парусам хватает веса UV.y.
		"riris":
			material.shader = GRASS_SHADER
			material.set_shader_parameter("use_gradient", 0.0)
			material.set_shader_parameter("wind_amplitude", 0.055)
			material.set_shader_parameter("wind_freq", 2.0)
			material.set_shader_parameter("fade_start", 42.0)
			material.set_shader_parameter("fade_end", 58.0)
		"mrock":
			material.shader = ROCK_SHADER
			_materialize_rock(material, VPAL.rock_rock, VPAL.rock_moss, 0.25)
		"rrock":
			material.shader = ROCK_SHADER
			# Доработка под эталон: рваные островки мха на верхних гранях —
			# не сплошная шапка и не голый камень.
			_materialize_rock(material, VPAL.rock_rock, VPAL.rock_moss, 0.55)
	_cache[type] = material
	return material


static func _materialize_rock(
		material: ShaderMaterial, rock: Color, moss: Color, edge: float,
) -> void:
	material.set_shader_parameter("rock_color", rock)
	material.set_shader_parameter("moss_color", moss)
	material.set_shader_parameter("moss_patch_strength", edge)


static func _flat() -> StandardMaterial3D:
	var flat := StandardMaterial3D.new()
	flat.vertex_color_use_as_albedo = true
	flat.roughness = 1.0
	return flat
