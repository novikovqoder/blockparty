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
# П12 E (SPEC 3.2): тон травы приглушён под палитру Born Unblessed — темнее
# и холоднее «пастельной сочности» Blockparty; правка общего файла — только
# константа тона (согласовано с владельцем на П11).
const GRASS_MUTE: Color = Color(0.80, 0.90, 0.76)
# Доработка-2 П5.13, П7: фактура мха камней — ambientCG Moss001 (CC0,
# та же, что мох кладки руинов).
const MOSS_TEX: Texture2D = preload(
	"res://assets/third_party/ambientcg.com/Moss001/Moss001_1K-JPG_Color.jpg")

static var _cache: Dictionary = {}

## Канонический спад густоты растительности (fade_start, fade_end), м —
## единый источник базы: материал кэшируется статически и живёт дольше
## одного IslandView, а IslandView._apply_grass_fade умножает fade
## по уровню. Без сброса база «уплывала» между видами (второй мир читал
## уже умноженное значение и множил снова — 40 → 34 → 51 → 43.35), поэтому
## при выдаче из кэша fade возвращается к канону.
static var _base_fade: Dictionary[String, Vector2] = {
	"rgrass": Vector2(40.0, 58.0),
	"fern": Vector2(45.0, 62.0),
	"rflower": Vector2(40.0, 56.0),
	"riris": Vector2(42.0, 58.0),
	"reed": Vector2(40.0, 58.0),
}


## Вернуть материалу растительности канонический спад (см. _base_fade):
## вызывается и при создании, и при каждом взятии из кэша.
static func _reset_fade(type: StringName, material: ShaderMaterial) -> void:
	if _base_fade.has(String(type)):
		var fade: Vector2 = _base_fade[String(type)]
		material.set_shader_parameter("fade_start", fade.x)
		material.set_shader_parameter("fade_end", fade.y)


## Тип обрабатывается этой фабрикой (IslandView._build_props). П5.13, блок 1:
## камни всего острова (boulder/rock_pillar/pebble) и камыш — тоже здесь:
## единый стиль мягких форм и мха, эталон Леса на всех зон.
static func handles(type: StringName) -> bool:
	return ["rgrass", "fern", "rflower", "riris", "mrock", "rrock",
		"boulder", "rock_pillar", "pebble", "reed"].has(String(type))


## Материал типа (трава — градиент; папоротник/цветы — цвет вершин;
## камни — мох). Амплитуда ветра у травы мелкая и частая, у вай — меньше.
static func for_type(type: StringName) -> Material:
	if WorldMaterials.want_flat():
		return _flat()
	if _cache.has(type):
		# Материал один на все виды мира — сброс спада к канону (иначе
		# база уплывает вместе с применёнными множителями уровней).
		_reset_fade(type, _cache[type])
		return _cache[type]
	var material := ShaderMaterial.new()
	match String(type):
		"rgrass":
			material.shader = GRASS_SHADER
			material.set_shader_parameter("use_gradient", 1.0)
			# П12 E: приглушённый тон (GRASS_MUTE) — и у печёных пучков,
			# и у рантайм-буста IslandView (материал общий).
			material.set_shader_parameter("base_color", VPAL.grass_base * GRASS_MUTE)
			material.set_shader_parameter("tip_color", VPAL.grass_tip * GRASS_MUTE)
			# Доработка под эталон: ветер заметен волнами по поляне —
			# кончик травинки гуляет до ~15 см в порыве.
			material.set_shader_parameter("wind_amplitude", 0.11)
			material.set_shader_parameter("wind_freq", 1.8)
		"fern":
			material.shader = GRASS_SHADER
			material.set_shader_parameter("use_gradient", 0.0)
			material.set_shader_parameter("wind_amplitude", 0.045)
			material.set_shader_parameter("wind_freq", 1.2)
		"rflower":
			material.shader = GRASS_SHADER
			material.set_shader_parameter("use_gradient", 0.0)
			material.set_shader_parameter("wind_amplitude", 0.04)
			material.set_shader_parameter("wind_freq", 2.2)
		# Ирис выше цветка — стебель качается шире, парусам хватает веса UV.y.
		"riris":
			material.shader = GRASS_SHADER
			material.set_shader_parameter("use_gradient", 0.0)
			material.set_shader_parameter("wind_amplitude", 0.055)
			material.set_shader_parameter("wind_freq", 2.0)
		"mrock":
			material.shader = ROCK_SHADER
			_materialize_rock(material, VPAL.rock_rock, VPAL.rock_moss, 0.25)
		"rrock":
			material.shader = ROCK_SHADER
			# Доработка под эталон: рваные островки мха на верхних гранях —
			# не сплошная шапка и не голый камень.
			_materialize_rock(material, VPAL.rock_rock, VPAL.rock_moss, 0.55)
		# П5.13, блок 1: камни вне Леса — тот же камень и мох, но мха мало
		# (площадь и холмы суше леса); скальные зубцы — почти голые.
		"boulder":
			material.shader = ROCK_SHADER
			_materialize_rock(material, VPAL.rock_rock, VPAL.rock_moss, 0.22)
		"rock_pillar":
			material.shader = ROCK_SHADER
			_materialize_rock(material, VPAL.rock_rock, VPAL.rock_moss, 0.12)
		"pebble":
			material.shader = ROCK_SHADER
			_materialize_rock(material, VPAL.rock_rock, VPAL.rock_moss, 0.18)
		# Камыш у воды — ветер заметнее лесной травы, гуще к верхушке
		# (початок самый подвижный: UV.y у него ~1).
		"reed":
			material.shader = GRASS_SHADER
			material.set_shader_parameter("use_gradient", 0.0)
			material.set_shader_parameter("wind_amplitude", 0.09)
			material.set_shader_parameter("wind_freq", 1.4)
	# Спад густоты — из канонической базы (_base_fade), не из match.
	_reset_fade(type, material)
	_cache[type] = material
	return material


static func _materialize_rock(
		material: ShaderMaterial, rock: Color, moss: Color, edge: float,
) -> void:
	material.set_shader_parameter("rock_color", rock)
	material.set_shader_parameter("moss_color", moss)
	material.set_shader_parameter("moss_patch_strength", edge)
	material.set_shader_parameter("moss_tex", MOSS_TEX)


static func _flat() -> StandardMaterial3D:
	var flat := StandardMaterial3D.new()
	flat.vertex_color_use_as_albedo = true
	flat.roughness = 1.0
	return flat
