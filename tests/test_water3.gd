# Тесты П15 «Вода, третья итерация»: попиксельные нормали во fragment
# (пп. 1-2), движковое отражение неба (п. 3), пена по SDF-карте берега
# и мягкий край (пп. 4, 9.2-9.4), полоса берега 0.25 м с бикубикой
# (п. 9.1), каустика и круги (пп. 5-6), галочки и ползунки F3 (пп. 7-8).
# Сервер — без рендера: шейдерное поведение проверяется материалом
# (uniform по уровням) и исходником шейдера, как test_ground_water2.
extends GutTest

const ART: IslandArt = preload("res://gameplay/world/island_art.res")
const WATER_BU_CODE: String = WaterArea.WATER_BU.code
const WATER_CHEAP_CODE: String = WaterArea.WATER_BU_CHEAP.code


# --- П15 1-2: нормали во fragment, фильтрация с расстоянием ---

func test_normals_in_fragment_vertex_displacement_only() -> void:
	# П15 1: нормали всего спектра — попиксельно во fragment по
	# world_pos; в vertex() — только смещение длинных волн (> 20 м),
	# никаких нормалей и гребней там не считается.
	for pair: Array in [
		["полный", WATER_BU_CODE], ["дешёвый", WATER_CHEAP_CODE],
	]:
		var code: String = pair[1]
		var vertex_part: String = code.substr(
			code.find("void vertex()"), code.find("void fragment()")
			- code.find("void vertex()"))
		assert_true(vertex_part.contains("VERTEX += disp"),
			"%s: vertex смещает геометрию" % pair[0])
		assert_true(vertex_part.contains("VERTEX_WAVE_M"),
			"%s: смещение — только волны длиннее порога" % pair[0])
		assert_false(vertex_part.contains("nrm"),
			"%s: в vertex нет расчёта нормали" % pair[0])
		assert_false(vertex_part.contains("crest"),
			"%s: в vertex нет гребней пены" % pair[0])
		var fragment_part: String = code.substr(code.find("void fragment()"))
		assert_true(fragment_part.contains("nrm.x -= wa.x * wa_slope"),
			"%s: нормали Герстнера — во fragment" % pair[0])
		assert_true(fragment_part.contains("float weight = wave_weight("),
			"%s: волны взвешиваются пиксельной фильтрацией" % pair[0])
	# Порог длинных волн — 20 м (SPEC П15 1: длиннее — в vertex).
	assert_almost_eq(_const_of(WATER_BU_CODE, "VERTEX_WAVE_M"), 20.0, 0.001,
		"порог длинных волн 20 м")
	assert_almost_eq(
		_const_of(WATER_CHEAP_CODE, "VERTEX_WAVE_M"), 20.0, 0.001,
		"дешёвая версия: тот же порог")


func test_normal_independent_of_mesh_density() -> void:
	# П15 1: нормаль не зависит от плотности сетки — в шейдере нет
	# производных по вершинам (dFdx/dFdx нормали из varying): наклон
	# волн аналитический по мировым координатам.
	for pair: Array in [
		["полный", WATER_BU_CODE], ["дешёвый", WATER_CHEAP_CODE],
	]:
		assert_false((pair[1] as String).contains("dFdx"),
			"%s: нет экранно-пространственных производных" % pair[0])
		assert_true((pair[1] as String).contains(
			"wa.z * dot(wa.xy, world_pos.xz)"),
			"%s: фаза волн — по мировой позиции" % pair[0])


func test_pixel_filter_roughness_grows_with_distance() -> void:
	# П15 2: Toksvig-подобная фильтрация — волны мельче 2-4 пикселей
	# гаснут, потерянный наклон переводится в рост roughness от
	# roughness_near (вблизи) к roughness_far (у горизонта).
	for pair: Array in [
		["полный", WATER_BU_CODE], ["дешёвый", WATER_CHEAP_CODE],
	]:
		var code: String = pair[1]
		assert_almost_eq(_const_of(code, "FILTER_MIN_PX"), 2.0, 0.001,
			"%s: мельче 2 пикселей — гаснут" % pair[0])
		assert_almost_eq(_const_of(code, "FILTER_MAX_PX"), 4.0, 0.001,
			"%s: крупнее 4 пикселей — целиком" % pair[0])
		assert_true(code.contains(
			"float rough = mix(roughness_near, roughness_far, lost);"),
			"%s: потерянный наклон уходит в roughness" % pair[0])
		assert_lt(_uniform_of(code, "roughness_near"),
			_uniform_of(code, "roughness_far"),
			"%s: near < far (roughness растёт с расстоянием)" % pair[0])
	assert_between(_uniform_of(WATER_BU_CODE, "roughness_near"), 0.02, 0.05,
		"вблизи — почти зеркало (0.03)")
	assert_between(_uniform_of(WATER_BU_CODE, "roughness_far"), 0.12, 0.2,
		"у горизонта — матовое зеркало (0.12-0.2)")
	# Размер экрана для фильтрации — uniform (в headless/material тоже).
	WorldMaterials.textured_headless = true
	var area := WaterArea.new()
	add_child_autofree(area)
	var material := area._surface_material(false) as ShaderMaterial
	var px_height: float = float(
		material.get_shader_parameter("screen_px_height"))
	assert_gt(px_height, 0.0, "высота экрана задана")
	assert_ne(px_height, 720.0, "высота экрана — не дефолт шейдера")
	WorldMaterials.textured_headless = false


func test_ripple_smaller_and_weaker() -> void:
	# П15 2: рябь мельче (0.3-1.5 м) и слабее прежней (2.2-0.55 м,
	# наклоны 0.030-0.016), та же пиксельная фильтрация.
	var code := WATER_BU_CODE
	assert_true(code.contains("0.667 * scale"),
		"базовый слой ряби — 1.5 м (1/0.667)")
	assert_true(code.contains("1.333 * scale"),
		"второй слой ряби — 0.75 м")
	assert_true(code.contains("3.333 * scale"),
		"третий слой ряби — 0.3 м")
	assert_false(code.contains("0.45, 0.35, TIME) * 0.030"),
		"прежняя сильная рябь 2.2 м ушла")
	assert_true(code.contains("float lambda_ripple = 1.5 / scale;"),
		"длина базового слоя ряби — 1.5 м")
	assert_true(code.contains(
		"wave_weight(lambda_ripple, dist, px_per_rad)"),
		"рябь фильтруется тем же весом")
	assert_true(code.contains("wave_weight(0.75 / scale, dist, px_per_rad)"),
		"второй слой ряби фильтруется")
	assert_true(code.contains("wave_weight(0.30 / scale, dist, px_per_rad)"),
		"третий слой ряби фильтруется")


# --- П15 3: движковое отражение неба ---

func test_engine_sky_reflection() -> void:
	# П15 3: ambient_light_disabled (отключает IBL-отражения) убран из
	# обоих шейдеров; ручного двухцветного неба (sky_horizon/sky_top)
	# больше нет — отражение и френель движковые (F0 ≈ 0.02 при
	# SPECULAR 0.25), дорожка светила — спекуляр движка. Пропущенный
	# свет (дно + рассеяние) гасится своим френелем Шлика: под острым
	# углом видно небо, сверху — толща.
	for pair: Array in [
		["полный", WATER_BU_CODE], ["дешёвый", WATER_CHEAP_CODE],
	]:
		var code: String = pair[1]
		assert_false(code.contains("ambient_light_disabled"),
			"%s: ambient_light_disabled убран (IBL работает)" % pair[0])
		assert_false(code.contains("uniform vec3 sky_horizon"),
			"%s: двухцветного неба нет" % pair[0])
		assert_false(code.contains("uniform vec3 sky_top"),
			"%s: неба в зените нет" % pair[0])
		assert_false(code.contains("sky_refl"),
			"%s: ручного отражения неба нет" % pair[0])
		assert_almost_eq(_uniform_of(code, "specular"), 0.25, 0.001,
			"%s: F0 ≈ 0.02 (SPECULAR × 0.08)" % pair[0])
	assert_true(WATER_BU_CODE.contains(
		"EMISSION = water * (1.0 - fresnel) * dist_fade;"),
		"пропущенный свет в EMISSION гасится френелем")
	assert_true(WATER_CHEAP_CODE.contains(
		"EMISSION = water * (1.0 - fresnel) * dist_fade;"),
		"дешёвая версия — тот же баланс")
	# WaterArea не красит материалы цветами неба (неба в шейдере нет).
	var area_text := FileAccess.get_file_as_string(
		"res://gameplay/world/water_area.gd")
	assert_false(area_text.contains('"sky_horizon"'),
		"WaterArea не пишет sky_horizon в материалы")
	assert_false(area_text.contains('"sky_top"'),
		"WaterArea не пишет sky_top в материалы")
	WorldMaterials.textured_headless = true
	var area := WaterArea.new()
	add_child_autofree(area)
	var material := area._surface_material(false) as ShaderMaterial
	assert_almost_eq(
		float(material.get_shader_parameter("specular")), 0.25, 0.001,
		"SPECULAR 0.25 в материале (F0 ≈ 0.02)")
	WorldMaterials.textured_headless = false


static func _const_of(code: String, name: String) -> float:
	var regex := RegEx.new()
	regex.compile("const float %s = ([\\d.]+);" % name)
	var found := regex.search(code)
	if found == null:
		push_error("константа %s не найдена" % name)
		return -1.0
	return float(found.get_string(1))


static func _uniform_of(code: String, name: String) -> float:
	var regex := RegEx.new()
	regex.compile("uniform float %s[^=]*= (-?[\\d.]+);" % name)
	var found := regex.search(code)
	if found == null:
		push_error("uniform %s не найден" % name)
		return -1.0
	return float(found.get_string(1))
