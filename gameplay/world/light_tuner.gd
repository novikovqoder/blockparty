# Подбор света на живом рендере (П18-ЛАБОРАТОРИЯ, п. 4 владельца): ползунки
# F3 → «Свет» перекрывают расчёты DayCycle — работают и в лаборатории
# ezTree (scenes/ez_lab.gd), и в мире. Ничего не сохраняется: дефолты —
# текущий свет мира днём (Balance/VisualPalette), «Сбросить» возвращает
# цикл дня в ведение DayCycle, значения живут в статике до перезапуска.
# Владелец подгоняет картинку к демо www.eztree.dev и присылает текст
# «Скопировать значения» — следующим этапом числа станут светом мира.
class_name LightTuner
extends RefCounted

## Дефолты = день мира (те же числа, что ставит DayCycle/world_scene.tscn
## и сцена лаборатории). Порядок — порядок вкладки «Свет».
const DEFS: Dictionary = {
	&"sun_energy": 0.3,
	&"sun_color": Color(1.0, 0.945098, 0.839216),
	&"sun_elevation": 62.0,
	&"ambient_color": Color(0.756863, 0.807843, 0.898039),
	&"ambient_energy": 0.546,  # = DayMath.ambient_energy_sky(полдень), bu-claude
	&"ambient_sky": true,
	&"tonemap": 4,
	&"exposure": 1.0,
	&"saturation": 1.15,
	&"contrast": 1.05,
	&"fog_color": Color(0.580392, 0.725490, 0.952941),
	&"fog_density": 0.0035,
	&"fog_on": true,
	&"leaf_color": Color.WHITE,
	&"leaf_brightness": 1.0,
	&"leaf_glow": 0.0,
	&"bark_color": Color.WHITE,
}
## Имена режимов тонмаппинга для текста «Скопировать значения»
## (индексы Environment.ToneMapper).
const TONEMAP_NAMES: PackedStringArray = [
	"Linear", "Reinhard", "Filmic", "ACES", "AgX",
]
## Направление НА солнце полудня мира (DayMath: высота 62°, азимут 0;
## sin/cos 62° литералами — не константные выражения) — старт
## лаборатории и запас, когда DayCycle ещё не передал своё.
const NOON_SUN_DIR: Vector3 = Vector3(0.0, 0.882948, 0.469472)

static var _values: Dictionary = {}
## Последнее направление НА солнце (мир — от DayCycle каждый кадр,
## лаборатория — от EzLab): ползунок высоты сохраняет азимут солнца.
static var _last_sun_dir: Vector3 = NOON_SUN_DIR
## Материалы деревьев (canopy/bark) активной сцены — красят ползунки
## листвы/коры; собираются заново при смене сцены (DebugPanel._ready).
static var _canopy_mats: Array[ShaderMaterial] = []
static var _bark_mats: Array[ShaderMaterial] = []


static func _ensure_values() -> void:
	if _values.is_empty():
		_values = DEFS.duplicate(true)


## Текущее значение параметра.
static func value(id: StringName) -> Variant:
	_ensure_values()
	return _values[id]


## Активен ли ползунок (значение ушло от дефолта): неактивные не
## перекрывают DayCycle — мир живёт как до лаборатории.
static func active(id: StringName) -> bool:
	_ensure_values()
	var def: Variant = DEFS[id]
	var val: Variant = _values[id]
	if def is Color:
		var c1: Color = def
		var c2: Color = val
		return not (is_equal_approx(c1.r, c2.r)
			and is_equal_approx(c1.g, c2.g)
			and is_equal_approx(c1.b, c2.b))
	if def is float:
		return not is_equal_approx(float(def), float(val))
	if def is bool:
		return bool(def) != bool(val)
	return def != val


## Есть ли хоть один активный ползунок (быстрая проверка хука DayCycle).
static func any_active() -> bool:
	_ensure_values()
	for id: StringName in DEFS:
		if active(id):
			return true
	return false


## Записать значение ползунка. Дерево-параметры (leaf_*/bark_*) красят
## материалы сразу; сцену применяет вызвавший (панель или кадр DayCycle).
static func set_value(id: StringName, val: Variant) -> void:
	_ensure_values()
	_values[id] = val
	if id == &"leaf_color" or id == &"leaf_brightness" or id == &"leaf_glow" \
			or id == &"bark_color":
		apply_tree_materials()


## Полный сброс: все значения — дефолты (DayCycle снова ведёт мир сам),
## материалы деревьев — нейтральные множители.
static func reset() -> void:
	_values = DEFS.duplicate(true)
	apply_tree_materials()


## Применить активные ползунки к сцене. Мир зовёт DayCycle из _process
## (после своих расчётов, передав направление солнца), лаборатория —
## панель F3 по изменению ползунка. Неактивные параметры не трогаются:
## их по-прежнему ведёт DayCycle (мир) или стартовая сборка сцены (лабо-
## ратория). dome — купол Sky3D мира (в лаборатории null: там своё небо-
## градиент и DirectionalLight3D).
static func apply_scene(
		env: Environment,
		sun: DirectionalLight3D,
		dome: SkyDome,
		sun_dir: Vector3 = Vector3.ZERO,
) -> void:
	if env == null:
		return
	if sun_dir.length_squared() > 0.5:
		_last_sun_dir = sun_dir.normalized()
	if not any_active():
		return
	_apply_fields(env, sun, dome, false)


## «Сбросить» (панель F3): разово вернуть ВСЕ поля сцены к дефолтам —
## в лаборатории это исходная картинка; в мире следующий кадр DayCycle
## перепишет всё расчётом суток (apply_scene неактивного не пишет).
static func apply_defaults(
		env: Environment, sun: DirectionalLight3D, dome: SkyDome,
) -> void:
	if env == null:
		return
	_apply_fields(env, sun, dome, true)


## Общий проход присваиваний: all = false — только активные ползунки,
## all = true — все поля в дефолт («Сбросить»).
static func _apply_fields(
		env: Environment,
		sun: DirectionalLight3D,
		dome: SkyDome,
		all: bool,
) -> void:
	var vals: Dictionary = {}
	for id: StringName in DEFS:
		if all or active(id):
			vals[id] = DEFS[id] if all else _values[id]
	var dir := _last_sun_dir
	if vals.has(&"sun_elevation"):
		# Высота солнца: азимут остаётся текущим (мир — по часам суток).
		var flat := Vector3(dir.x, 0.0, dir.z)
		if flat.length_squared() < 0.000001:
			flat = Vector3(0.0, 0.0, 1.0)
		var elev := deg_to_rad(float(vals[&"sun_elevation"]))
		dir = flat.normalized() * cos(elev) + Vector3.UP * sin(elev)
	if vals.has(&"sun_energy") and sun != null:
		sun.light_energy = float(vals[&"sun_energy"])
		if dome != null:
			dome.sun_light_energy = float(vals[&"sun_energy"])
	if vals.has(&"sun_color") and sun != null:
		sun.light_color = vals[&"sun_color"] as Color
		if dome != null:
			dome.sun_light_color = vals[&"sun_color"] as Color
	if vals.has(&"sun_elevation"):
		if dome != null:
			dome.sun_altitude = acos(clampf(dir.y, -1.0, 1.0))
			dome.sun_azimuth = atan2(dir.x, dir.z)
		elif sun != null:
			sun.global_position = dir * 100.0
			# В зените/надире цель ровно по up-вектору — коллинеарно,
			# Godot сыплет ошибкой вращения; up наклоняем вперёд.
			var up := (
				Vector3.UP if absf(dir.y) < 0.999
				else Vector3.FORWARD)
			sun.look_at(Vector3.ZERO, up)
	if vals.has(&"ambient_color"):
		env.ambient_light_color = vals[&"ambient_color"] as Color
	if vals.has(&"ambient_energy"):
		env.ambient_light_energy = float(vals[&"ambient_energy"])
	if vals.has(&"ambient_sky"):
		env.ambient_light_source = (
			Environment.AMBIENT_SOURCE_SKY
			if bool(vals[&"ambient_sky"])
			else Environment.AMBIENT_SOURCE_COLOR)
	if vals.has(&"tonemap"):
		env.tonemap_mode = int(vals[&"tonemap"]) as Environment.ToneMapper
	if vals.has(&"exposure"):
		env.tonemap_exposure = float(vals[&"exposure"])
	if vals.has(&"saturation"):
		env.adjustment_saturation = float(vals[&"saturation"])
	if vals.has(&"contrast"):
		env.adjustment_contrast = float(vals[&"contrast"])
	if vals.has(&"fog_color"):
		env.fog_light_color = vals[&"fog_color"] as Color
	if vals.has(&"fog_density"):
		env.fog_density = float(vals[&"fog_density"])
	if vals.has(&"fog_on"):
		env.fog_enabled = bool(vals[&"fog_on"])
	if vals.has(&"leaf_glow"):
		for material: ShaderMaterial in _canopy_mats:
			material.set_shader_parameter("sun_dir_world", dir)


## Направление НА солнце от лаборатории (нет DayCycle — свет стоит как
## поставили ползунки); обновляет и glow-юниформ листвы.
static func set_lab_sun_dir(dir: Vector3) -> void:
	if dir.length_squared() < 0.5:
		return
	_last_sun_dir = dir.normalized()
	if active(&"leaf_glow"):
		for material: ShaderMaterial in _canopy_mats:
			material.set_shader_parameter("sun_dir_world", _last_sun_dir)


## Собрать материалы деревьев сцены (canopy/bark) и применить к ним
## текущие ползунки листвы/коры. Зовёт DebugPanel при создании панели —
## после построения деревьев сцены; повторный вызов пересобирает кэш.
static func bind_scene(root: Node) -> void:
	_canopy_mats.clear()
	_bark_mats.clear()
	if root != null:
		for node: Node in root.find_children(
				"*", "GeometryInstance3D", true, false):
			var mesh: Mesh = null
			if node is MeshInstance3D:
				mesh = (node as MeshInstance3D).mesh
			elif node is MultiMeshInstance3D:
				var mm := (node as MultiMeshInstance3D).multimesh
				if mm != null:
					mesh = mm.mesh
			if mesh == null:
				continue
			for surface: int in mesh.get_surface_count():
				var material := mesh.surface_get_material(surface)
				if material is not ShaderMaterial:
					continue
				var shader: Shader = (material as ShaderMaterial).shader
				if shader == EzTreeMeshes.CANOPY_SHADER:
					_canopy_mats.append(material as ShaderMaterial)
				elif shader == EzTreeMeshes.BARK_SHADER:
					_bark_mats.append(material as ShaderMaterial)
	apply_tree_materials()


## Ползунки деревьев: множители поверх тонов пресетов (leaf_tint пресета
## не трогается — нейтральный дефолт = белый не меняет картинку мира).
static func apply_tree_materials() -> void:
	var leaf_color: Color = DEFS[&"leaf_color"]
	var leaf_brightness: float = DEFS[&"leaf_brightness"]
	var leaf_glow: float = DEFS[&"leaf_glow"]
	var bark_color: Color = DEFS[&"bark_color"]
	_ensure_values()
	if _values.has(&"leaf_color"):
		leaf_color = _values[&"leaf_color"]
	if _values.has(&"leaf_brightness"):
		leaf_brightness = float(_values[&"leaf_brightness"])
	if _values.has(&"leaf_glow"):
		leaf_glow = float(_values[&"leaf_glow"])
	if _values.has(&"bark_color"):
		bark_color = _values[&"bark_color"]
	for material: ShaderMaterial in _canopy_mats:
		material.set_shader_parameter("leaf_tint_mul", leaf_color)
		material.set_shader_parameter("leaf_brightness", leaf_brightness)
		material.set_shader_parameter("leaf_glow", leaf_glow)
		material.set_shader_parameter("sun_dir_world", _last_sun_dir)
	for material: ShaderMaterial in _bark_mats:
		material.set_shader_parameter("bark_tint", bark_color)


## Текст «Скопировать значения»: все параметры с числами — владелец
## присылает его в чат, следующим этапом числа становятся светом мира.
static func build_values_text() -> String:
	_ensure_values()
	var lines: Array[String] = []
	for id: StringName in DEFS:
		var val: Variant = _values[id]
		if val is Color:
			var c: Color = val
			lines.append("%s = Color(%.3f, %.3f, %.3f)" % [id, c.r, c.g, c.b])
		elif id == &"tonemap":
			lines.append("%s = %s (%d)" % [id,
				TONEMAP_NAMES[int(val)], int(val)])
		elif val is float:
			lines.append("%s = %.4f" % [id, float(val)])
		else:
			lines.append("%s = %s" % [id, str(val)])
	return "\n".join(lines)
