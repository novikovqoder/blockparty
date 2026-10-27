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
## Контрольная сумма heights печёного арта: П15 землю не трогает,
## карта высот (коллизия) обязана совпасть побитово.
const HEIGHTS_CHECKSUM: int = 2041845998


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
		"EMISSION = water * (1.0 - fresnel) * dist_fade"),
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


# --- П15 4 + 9.2-9.4: SDF-карта берега, пена, накат, мягкий край ---

func test_shore_sdf_signs_and_accuracy() -> void:
	# П15 9.3: SDF запечена из карты высот — суша > 0, вода < 0; у линии
	# берега ≈ 0; в полосе у берега совпадает с честным расстоянием до
	# изолинии (перебор точек пересечения) с точностью узлов карты (1 м)
	# и билинейной выборки.
	var art := ART
	var level: float = IslandGen.SEA_LEVEL
	var image := ShoreBand.sdf_image(art, level)
	assert_eq(image.get_width(), IslandGen.POINTS, "SDF — размер карты высот")
	assert_eq(image.get_format(), Image.FORMAT_RF, "SDF — RFloat")
	# Знаки: центр острова — суша, центр озера — вода.
	assert_gt(ShoreBand.sdf_at(image, 0.0, 0.0), 0.5,
		"центр острова — суша (SDF > 0)")
	assert_lt(ShoreBand.sdf_at(image, IslandGen.LAKE_CENTER.x,
		IslandGen.LAKE_CENTER.y), -0.5,
		"центр озера — вода (SDF < 0)")
	# Точность в полосе ±3 м от берега: честное расстояние перебором
	# точек контура против выборки карты.
	var heights: PackedFloat32Array = art.heights
	var contour := ShoreBand.contour_points(heights, level)
	assert_gt(contour.size(), 100, "контур острова найден")
	var worst: float = 0.0
	var checked: int = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261027
	for i: int in 40:
		var point: Vector2 = contour[rng.randi_range(0, contour.size() - 1)]
		# Проба на суше и в воде в 0.5-3 м от линии.
		var offset := Vector2(
			rng.randf_range(0.5, 3.0), 0.0).rotated(rng.randf() * TAU)
		for mult: float in [1.0, -1.0]:
			var probe := point + offset * mult
			probe = Vector2(
				clampf(probe.x, -120.0, 120.0),
				clampf(probe.y, -120.0, 120.0))
			var truth: float = ShoreBand.true_distance(
				heights, level, contour, probe.x, probe.y)
			if absf(truth) > 4.0:
				continue  # вне полосы точности (clamp SDF_RANGE)
			var got: float = ShoreBand.sdf_at(image, probe.x, probe.y)
			worst = maxf(worst, absf(got - truth))
			checked += 1
	assert_gt(checked, 40, "проверено достаточно проб у берега")
	assert_lte(worst, 0.75,
		"SDF в полосе берега совпадает с честным расстоянием (≤0.75 м)")


func test_foam_uses_sdf_not_depth() -> void:
	# П15 4 + 9.3: пена — по карте расстояния до берега (shore_sdf),
	# НЕ по толщине из буфера глубины; только smoothstep, без step(.
	var code := WATER_BU_CODE
	assert_true(code.contains("uniform sampler2D shore_sdf"),
		"карта SDF берега — uniform шейдера")
	assert_true(code.contains("float sdf = texture(shore_sdf"),
		"пена читает SDF-карту")
	assert_true(code.contains("1.0 - smoothstep(0.0, foam_width, line)"),
		"полоса пены — smoothstep по расстоянию до линии наката")
	# Пена больше не строится по толщине: FOAM_SHORE_M удалён.
	assert_false(code.contains("FOAM_SHORE_M"),
		"пены по толщине из depth больше нет")
	# В коде пены нет step( — только плавные переходы (smoothstep).
	var foam_part: String = code.substr(code.find("// Пена по SDF-карте"))
	assert_false(foam_part.replace("smoothstep(", "").contains("step("),
		"в пене нет резкого step(")
	assert_false(foam_part.contains("texture(depth_tex, refr_uv).g"),
		"пена не читает буфер глубины напрямую")
	# WaterArea ставит карту в материал (море и озеро — одна карта).
	WorldMaterials.textured_headless = true
	var area := WaterArea.new()
	add_child_autofree(area)
	var material := area._surface_material(false) as ShaderMaterial
	assert_not_null(material.get_shader_parameter("shore_sdf"),
		"карта SDF в материале воды")
	WorldMaterials.textured_headless = false


func test_foam_lit_by_scene_light() -> void:
	# П15 4: пена освещается светом сцены — ALBEDO = цвет пены × foam,
	# EMISSION воды гасится (1 − foam); непрозрачность ≤ 0.6; цвет
	# 0.75-0.8, не чисто белый. Свет в EMISSION пена не пишет.
	var code := WATER_BU_CODE
	assert_true(code.contains("ALBEDO = FOAM_COLOR * foam;"),
		"пена — в ALBEDO (освещается светом сцены)")
	assert_true(code.contains("* (1.0 - foam) * edge;"),
		"EMISSION воды гасится пеной и мягким краем")
	assert_true(code.contains("foam * 0.6"),
		"непрозрачность пены ≤ 0.6")
	# Цвет пены 0.75-0.8 по каналам, не чисто белый.
	var color_match := RegEx.new()
	color_match.compile(
		"const vec3 FOAM_COLOR = vec3\\(([\\d.]+), ([\\d.]+), ([\\d.]+)\\);")
	var found := color_match.search(code)
	assert_not_null(found, "константа цвета пены найдена")
	if found != null:
		for channel: String in [found.get_string(1), found.get_string(2),
			found.get_string(3)]:
			assert_between(float(channel), 0.75, 0.8,
				"цвет пены 0.75-0.8 (%s)" % channel)
	# Пена не светится сама: в строке EMISSION нет цвета пены.
	var emission_index: int = code.find("EMISSION = water")
	var emission_line: String = code.substr(
		emission_index, code.find("\n", emission_index) - emission_index)
	assert_false(emission_line.contains("FOAM_COLOR"),
		"пена не пишется в EMISSION напрямую")


func test_soft_edge_fades_all_but_bottom() -> void:
	# П15 9.2: последние 5-15 см толщины гасят отражение/френель/
	# рассеяние/рябь — вода у кромки полностью прозрачная; дно остаётся.
	var code := WATER_BU_CODE
	assert_between(_const_of(code, "EDGE_SOFT_M"), 0.05, 0.15,
		"мягкий край — 5-15 см толщины")
	assert_true(code.contains(
		"float edge = smoothstep(0.0, EDGE_SOFT_M, thickness);"),
		"гашение края — по толщине воды")
	assert_true(code.contains(
		"scatter * (1.0 - transmit) * edge"),
		"рассеяние гасится у кромки (дно — остаётся)")
	assert_true(code.contains(
		"SPECULAR = specular * edge * (1.0 - foam);"),
		"отражение неба гасится у кромки")
	assert_true(code.contains(
		"nrm = normalize(mix(vec3(0.0, 1.0, 0.0), nrm, edge));"),
		"рябь и наклон волн гасятся у кромки")
	assert_true(code.contains(
		"ALPHA = clamp(max(edge, foam * 0.6), 0.0, 1.0);"),
		"у кромки без пены альфа → 0 (полная прозрачность)")


func test_runup_follows_long_wave() -> void:
	# П15 9.4: накат 10-40 см (море сильнее, озеро чуть-чуть) — линия
	# пены ползёт туда-обратно в такт длинной волне спектра.
	var code := WATER_BU_CODE
	assert_true(code.contains("float runup = runup_amp"),
		"накат — амплитуда uniform")
	assert_true(code.contains("cos(TIME * min(waves_b[0].x * 0.35, 0.6))"),
		"фаза наката — от самой длинной волны спектра")
	assert_between(_uniform_of(code, "runup_amp"), 0.1, 0.4,
		"амплитуда наката в пределах 10-40 см (дефолт)")
	# Шумы двух масштабов рвут полосу: 0.2 м (×5.0) и 0.6 м (×1.667).
	assert_true(code.contains("world_pos.xz * 5.0"),
		"шум пены масштаба 0.2 м")
	assert_true(code.contains("world_pos.xz * 1.667"),
		"шум пены масштаба 0.6 м")
	# Море/озеро: база пены и амплитуда наката меньше у озера.
	assert_between(WaterArea.LAKE_FOAM, 0.05, 0.3,
		"озеро — почти без пены")
	assert_almost_eq(WaterArea.SEA_FOAM, 1.0, 0.001, "море — полная пена")
	assert_between(WaterArea.SEA_RUNUP, 0.10, 0.40, "море: накат 10-40 см")
	assert_between(WaterArea.LAKE_RUNUP, 0.02, 0.12,
		"озеро: накат чуть-чуть (< моря)")
	assert_lt(WaterArea.LAKE_RUNUP, WaterArea.SEA_RUNUP,
		"накат озера меньше морского")


func test_lake_material_foam_lower_than_sea() -> void:
	# П15 4: в материале озера пены почти нет (база 0.15), у моря —
	# номинал; ползунок множит базу зоны.
	WorldMaterials.textured_headless = true
	var sea := WaterArea.new()
	add_child_autofree(sea)
	var sea_material := sea._surface_material(false) as ShaderMaterial
	var lake := WaterArea.new()
	add_child_autofree(lake)
	var lake_material := lake._surface_material(true) as ShaderMaterial
	assert_almost_eq(
		float(sea_material.get_shader_parameter("foam_amount")), 1.0, 0.001,
		"море: количество пены — номинал")
	assert_almost_eq(
		float(lake_material.get_shader_parameter("foam_amount")),
		WaterArea.LAKE_FOAM, 0.001,
		"озеро: пены почти нет (база)")
	assert_almost_eq(
		float(lake_material.get_shader_parameter("runup_amp")),
		WaterArea.LAKE_RUNUP, 0.001, "озеро: накат минимален")
	# Ползунок F3 (set_foam) умножает базу зоны, а не выравнивает.
	lake.set_foam(0.5, 0.1)
	assert_almost_eq(
		float(lake_material.get_shader_parameter("foam_amount")),
		WaterArea.LAKE_FOAM * 0.5, 0.001,
		"ползунок умножает базу зоны (озеро остаётся почти без пены)")
	sea.set_foam(0.5, 0.1)
	assert_almost_eq(
		float(sea_material.get_shader_parameter("foam_amount")), 0.5, 0.001,
		"море: ползунок уменьшает пену")
	assert_almost_eq(
		float(sea_material.get_shader_parameter("foam_width")), 0.1, 0.001,
		"ширина полосы пены меняется")
	WorldMaterials.textured_headless = false


func test_island_heights_unchanged() -> void:
	# П15 9.1: генератор, карта высот и коллизия не меняются — печёный
	# арт острова несёт прежние высоты (полный хеш генерации закреплён
	# в test_island_gen; здесь — быстрая сверка heights арта).
	var heights: PackedFloat32Array = ART.heights
	assert_eq(heights.size(), IslandGen.POINTS * IslandGen.POINTS,
		"размер карты высот прежний")
	var checksum := 0
	for h: float in heights:
		checksum = hash([checksum, h])
	assert_eq(checksum, HEIGHTS_CHECKSUM,
		"карта высот арта не изменилась (хеш)")
