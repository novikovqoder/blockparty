# Тесты П15 «Вода, третья итерация»: попиксельные нормали во fragment
# (пп. 1-2), движковое отражение неба (п. 3), пена по SDF-карте берега
# и мягкий край (пп. 4, 9.2-9.4), полоса берега 0.25 м с бикубикой
# (п. 9.1), каустика и круги (пп. 5-6), галочки и ползунки F3 (пп. 7-8).
# П15-ДОП блок 2: пена туториала — маска мелководья + гребни по нормали
# + SDF-полоса, fbm-Вороной с domain warp, кромка и пузырьки.
# П15-ДОП блок 3: объёмный цвет тонирует дно, преломление с маской
# мелководья, каустика — произведение двух встречных слоёв.
# Сервер — без рендера: шейдерное поведение проверяется материалом
# (uniform по уровням) и исходником шейдера, как test_ground_water2.
extends GutTest

const ART: IslandArt = preload("res://gameplay/world/island_art.res")
const PLAYER: PackedScene = preload("res://gameplay/player/player.tscn")
const WATER_BU_CODE: String = WaterArea.WATER_BU.code
const WATER_CHEAP_CODE: String = WaterArea.WATER_BU_CHEAP.code
## Контрольная сумма heights печёного арта: П15 землю не трогает,
## карта высот (коллизия) обязана совпасть побитово.
const HEIGHTS_CHECKSUM: int = 2041845998


# --- П15 1-2: нормали во fragment, фильтрация с расстоянием ---

func test_normals_in_fragment_vertex_displacement_only() -> void:
	# П15-ДОП: волны sea_octave — смещение геометрии в vertex тремя
	# октавами (map геометрии), детальная нормаль — попиксельно во
	# fragment (wave_normal_detailed по world_pos); в vertex считается
	# только грубая геометрическая нормаль для дальнего сведения.
	for pair: Array in [
		["полный", WATER_BU_CODE], ["дешёвый", WATER_CHEAP_CODE],
	]:
		var code: String = pair[1]
		var vertex_part: String = code.substr(
			code.find("void vertex()"), code.find("void fragment()")
			- code.find("void vertex()"))
		assert_true(vertex_part.contains(
				"VERTEX.y += wave_height_geo(wp.xz, TIME)"),
			"%s: vertex смещает геометрию волнами" % pair[0])
		assert_true(vertex_part.contains("wave_height_geo"),
			"%s: смещение — геометрические октавы" % pair[0])
		assert_false(vertex_part.contains("wave_normal_detailed"),
			"%s: детальной нормали в vertex нет" % pair[0])
		assert_false(vertex_part.contains("crest"),
			"%s: в vertex нет гребней пены" % pair[0])
		var fragment_part: String = code.substr(code.find("void fragment()"))
		assert_true(fragment_part.contains(
				"wave_normal_detailed(world_pos.xz, lod_eps)"),
			"%s: детальная нормаль волн — во fragment" % pair[0])
		assert_true(fragment_part.contains("float weight = wave_weight("),
			"%s: рябь взвешивается пиксельной фильтрацией" % pair[0])
	# Функции туториала: 3 октавы геометрии, до 5 на нормаль.
	for code: String in [WATER_BU_CODE, WATER_CHEAP_CODE]:
		assert_true(code.contains("float sea_octave("),
			"октавы волн — sea_octave (туториал)")
		assert_true(code.contains("const int ITER_GEOMETRY = 3;"),
			"геометрия — 3 октавы")
		assert_true(code.contains("const mat2 octave_m"),
			"матрица сжатия октав — octave_m")
	assert_true(WATER_BU_CODE.contains("const int ITER_FRAGMENT_MAX = 5;"),
		"полный шейдер: до 5 октав нормали")
	assert_true(WATER_BU_CODE.contains("uniform int iter_fragment"),
		"октавы нормали — по уровню качества")


func test_normal_independent_of_mesh_density() -> void:
	# П15 1: нормаль не зависит от плотности сетки — в шейдере нет
	# производных по вершинам (dFdx нормали из varying): высота волн
	# считается по мировым координатам конечными разностями.
	for pair: Array in [
		["полный", WATER_BU_CODE], ["дешёвый", WATER_CHEAP_CODE],
	]:
		assert_false((pair[1] as String).contains("dFdx"),
			"%s: нет экранно-пространственных производных" % pair[0])
		assert_true((pair[1] as String).contains(
			"wave_normal_detailed(world_pos.xz"),
			"%s: нормаль волн — по мировой позиции" % pair[0])
		assert_true((pair[1] as String).contains(
			"float wave_height_geo(vec2 xz"),
			"%s: высота волн — функция мировой позиции" % pair[0])


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
	# П15-ДОП: шаг конечных разностей нормали растёт с расстоянием
	# (детали вдали гаснут, а не мерцают), нормаль сводится к
	# геометрической за NORMAL_SMOOTH_DIST.
	for pair: Array in [
		["полный", WATER_BU_CODE], ["дешёвый", WATER_CHEAP_CODE],
	]:
		var code: String = pair[1]
		assert_true(code.contains("max(NORMAL_EPS_M, dist * 0.005)"),
			"%s: шаг разностей растёт с дистанцией" % pair[0])
		assert_almost_eq(_const_of(code, "NORMAL_SMOOTH_DIST"), 50.0, 0.001,
			"%s: сведение к геометрической нормали — с 50 м" % pair[0])
		assert_true(code.contains(
			"mix(nrm, vertex_normal_world, smooth_factor)"),
			"%s: вдали нормаль — геометрическая (vertex)" % pair[0])
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
	# П15 4 + 9.3 + П15-ДОП блок 2: линия берега — по карте расстояния
	# до берега (shore_sdf), не по рёбрам треугольников depth; маска
	# мелководья по толщине и гребни по нормали — слагаемые туториала.
	# Только smoothstep, без step(.
	var code := WATER_BU_CODE
	assert_true(code.contains("uniform sampler2D shore_sdf"),
		"карта SDF берега — uniform шейдера")
	assert_true(code.contains("float sdf = texture(shore_sdf"),
		"пена читает SDF-карту")
	assert_true(code.contains(
			"1.0 - smoothstep(0.0, foam_width, shore_line)"),
		"полоса пены — smoothstep по расстоянию до линии наката")
	assert_false(code.contains("FOAM_SHORE_M"),
		"старой константы полосы по depth нет")
	# В коде пены нет step( — только плавные переходы (smoothstep).
	var foam_part: String = code.substr(code.find("// Пена туториала"))
	assert_false(foam_part.replace("smoothstep(", "").contains("step("),
		"в пене нет резкого step(")
	assert_false(foam_part.contains("texture(depth_tex, refr_uv).g"),
		"пена не читает буфер глубины напрямую")
	# Предмет над водой в кадре не покрывается пеной (толщина вдоль
	# взгляда отрицательна) — как проверка туториала.
	assert_true(code.contains("thickness_signed > 0.0"),
		"пена — только под водой (предмет над водой чист)")
	# WaterArea ставит карту в материал (море и озеро — одна карта).
	WorldMaterials.textured_headless = true
	var area := WaterArea.new()
	add_child_autofree(area)
	var material := area._surface_material(false) as ShaderMaterial
	assert_not_null(material.get_shader_parameter("shore_sdf"),
		"карта SDF в материале воды")
	WorldMaterials.textured_headless = false


func test_foam_tutorial_masks_and_voronoi() -> void:
	# П15-ДОП блок 2: маска пены туториала — мелководье (толщина) +
	# гребни (нормаль) + наша SDF-полоса; масса — анимированный fbm
	# Вороного с domain warp и emergence-пульсацией; кромка — смещённая
	# выборка той же массы, пузырьки — отдельный мелкий Вороной.
	var code := WATER_BU_CODE
	# Маска: три слагаемых, всё умножается на foam_amount зоны.
	assert_true(code.contains(
			"smoothstep(FOAM_DEPTH_START, FOAM_DEPTH_END,"),
		"мелководье — по толщине воды (туториал)")
	assert_true(code.contains("smoothstep(FOAM_CREST_THRESHOLD,"),
		"гребни — по нормали (nrm.y ниже порога)")
	assert_true(code.contains("FOAM_CREST_THRESHOLD - 0.1, nrm.y"),
		"порог гребней — наклон нормали")
	assert_true(code.contains("* foam_amount * underwater"),
		"маска умножается на количество пены зоны")
	# Функции туториала.
	for pair: Array in [["float hash13(", "hash13"], ["vec2 hash22(", "hash22"],
			["float voronoi(", "voronoi"], ["float noise3d(", "noise3d"],
			["float fbm_voronoi(", "fbm_voronoi"]]:
		assert_true(code.contains(pair[0]),
			"функция пены %s (туториал)" % pair[1])
	assert_true(code.contains("sin(TIME * FOAM_NOISE_SPEED + 6.2831 * o)"),
		"точки Вороного анимированы (живые комья)")
	assert_true(code.contains("val = pow(val, 2.0);"),
		"октавы Вороного заострены pow")
	# Domain warp двумя шумами, emergence — 3D value-шум.
	assert_true(code.contains("vnoise(flow_uv + vec2(5.2, 1.3))"),
		"domain warp — два шума со сдвигом фазы")
	assert_true(code.contains(
			"noise3d(vec3(world_pos.xz * 0.5,"),
		"emergence — 3D-шум пульсации комьев")
	assert_true(code.contains("mix(emergence, 1.0, foam_level)"),
		"у берега и гребней emergence полный")
	# Масса и кромка: смещённая выборка, мягкий порог.
	assert_true(code.contains(
			"smoothstep(FOAM_CUTOFF + 0.5, FOAM_CUTOFF + 0.6,"),
		"порог массы пены — smoothstep")
	assert_true(code.contains("(world_pos.xz + FOAM_EDGE_OFFSET)"),
		"кромка — смещённая выборка той же массы")
	assert_true(code.contains(
			"clamp(shadow_shape - foam_mask, 0.0, 1.0)"),
		"тёмная кромка — там, где массы нет")
	# Пузырьки: мелкий Вороной рвёт массу изнутри.
	assert_true(code.contains("1.0 - sqrt(voronoi("),
		"пузырьки — отдельный мелкий Вороной")
	assert_true(code.contains("* foam_bubbles, 0.0, 1.0)"),
		"плотность пузырьков — uniform")
	# Круги вокруг ног входят в ту же массу.
	assert_true(code.contains("foam_mask = max(foam_mask, rings_foam)"),
		"пена кругов входит в общую пену воды")
	# П15-ДОП блок 6: Вороной — только там, где пена возможна; открытая
	# вода платит только дешёвыми масками (цена на HIGH).
	assert_true(code.contains(
			"if (foam_level > 0.001 || rings_foam > 0.001) {"),
		"масса пены — за ветвлением по маске пены")


func test_foam_lit_by_scene_light() -> void:
	# П15 4: пена освещается светом сцены — ALBEDO = цвет массы поверх
	# тёмной кромки × маски, EMISSION воды гасится (1 − foam);
	# непрозрачность ≤ 0.6; цвет 0.75-0.8, не чисто белый. Свет в
	# EMISSION пена не пишет.
	var code := WATER_BU_CODE
	assert_true(code.contains("ALBEDO = foam_edge_color.rgb")
		and code.contains("+ foam_color.rgb * foam_mask;"),
		"пена — в ALBEDO (освещается светом сцены)")
	assert_true(code.contains("* (1.0 - foam) * edge;"),
		"EMISSION воды гасится пеной и мягким краем")
	assert_true(code.contains("foam * 0.6"),
		"непрозрачность пены ≤ 0.6")
	assert_true(code.contains("mix(rough, 0.8, foam)"),
		"пена шершавая (roughness → 0.8, туториал)")
	# Цвет пены 0.75-0.8 по каналам, не чисто белый; кромка тёмная.
	for channel: float in [WaterArea.FOAM_COLOR.r, WaterArea.FOAM_COLOR.g,
			WaterArea.FOAM_COLOR.b]:
		assert_between(channel, 0.75, 0.8,
			"цвет пены 0.75-0.8 (%.2f)" % channel)
	assert_lt(WaterArea.FOAM_EDGE_COLOR.get_luminance(), 0.1,
		"кромка пены — тёмный ободок")
	assert_lt(WaterArea.FOAM_EDGE_COLOR.get_luminance(),
		WaterArea.FOAM_COLOR.get_luminance(),
		"кромка темнее массы пены")
	# Пена не светится сама: в строке EMISSION нет цвета пены.
	var emission_index: int = code.find("EMISSION = water")
	var emission_line: String = code.substr(
		emission_index, code.find("\n", emission_index) - emission_index)
	assert_false(emission_line.contains("foam_color"),
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
	# пены ползёт туда-обратно; такт — период морской зыби константой
	# (спектра волн больше нет, П15-ДОП).
	var code := WATER_BU_CODE
	assert_true(code.contains("float runup = runup_amp"),
		"накат — амплитуда uniform")
	assert_true(code.contains("cos(TIME * TAU / RUNUP_PERIOD_SEC)"),
		"фаза наката — период зыби константой")
	assert_between(_const_of(code, "RUNUP_PERIOD_SEC"), 4.0, 12.0,
		"период наката — секунды морской зыби")
	assert_between(_uniform_of(code, "runup_amp"), 0.1, 0.4,
		"амплитуда наката в пределах 10-40 см (дефолт)")
	# Шум 0.6 м волнист линию наката (мелкую рваность ей даёт Вороной
	# массы пены, П15-ДОП блок 2).
	assert_true(code.contains("world_pos.xz * 1.667"),
		"шум волнистости линии — масштаб 0.6 м")
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
	# Пена туториала (П15-ДОП блок 2): цвета и номиналы кромки/пузырьков
	# WaterArea ставит в материал обеих зон.
	for material: ShaderMaterial in [sea_material, lake_material]:
		assert_eq(material.get_shader_parameter("foam_color"),
			WaterArea.FOAM_COLOR, "цвет массы пены — константа зоны")
		assert_eq(material.get_shader_parameter("foam_edge_color"),
			WaterArea.FOAM_EDGE_COLOR, "цвет кромки пены — константа зоны")
		assert_almost_eq(
			float(material.get_shader_parameter("foam_edge")),
			WaterArea.FOAM_EDGE, 0.001, "номинал силы кромки")
		assert_almost_eq(
			float(material.get_shader_parameter("foam_bubbles")),
			WaterArea.FOAM_BUBBLES, 0.001, "номинал плотности пузырьков")
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


# --- П15 9.1: полоса берега — шаг 0.25 м, бикубика, отклонение ≤5 см ---

func test_band_mesh_built_with_quarter_step() -> void:
	# П15 9.1: полоса сетки вдоль всей береговой линии с шагом 0.25 м —
	# вершины лежат на решётке 0.25, рёбра подквадов по горизонтали
	# 0.25 (диагонали — 0.354); меш непустой и индексный.
	var mesh := ShoreBand.build_band_mesh(ART, IslandGen.SEA_LEVEL)
	assert_gt(mesh.get_surface_count(), 0, "полоса построена")
	var surface: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = surface[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = surface[Mesh.ARRAY_INDEX]
	assert_gt(verts.size(), 10000, "полоса покрывает всю береговую линию")
	assert_eq(idx.size() % 3, 0, "треугольники целые")
	var worst_step: float = 0.0
	for i: int in range(0, idx.size(), 3):
		for k: int in 3:
			var a: Vector3 = verts[idx[i + k]]
			var b: Vector3 = verts[idx[i + (k + 1) % 3]]
			# Рёбра подквада: два по осям (0.25) и диагональ (0.354) —
			# осевые проверяются точно, диагональ своим значением.
			var planar: float = Vector2(a.x, a.z).distance_to(
				Vector2(b.x, b.z))
			if absf(planar - 0.3536) > 0.001:
				worst_step = maxf(worst_step, absf(planar - 0.25))
	assert_lte(worst_step, 0.001,
		"горизонтальный шаг сетки полосы — 0.25 м")


func test_band_mesh_within_5cm_of_collision() -> void:
	# П15 9.1: отклонение визуальной высоты полосы от коллизии — не
	# больше 5 см. Высота коллизии (HeightMapShape3D, Jolt режет квад
	# диагональю (x+1,z)–(x,z+1) — проверено raycast-пробником на
	# седловой клетке) сверяется честным raycast по подмножеству вершин
	# и аналитически по всем.
	var mesh := ShoreBand.build_band_mesh(ART, IslandGen.SEA_LEVEL)
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[
		Mesh.ARRAY_VERTEX]
	var heights: PackedFloat32Array = ART.heights
	var worst: float = 0.0
	for v: Vector3 in verts:
		var col: float = ShoreBand.collision_height(heights, v.x, v.z)
		worst = maxf(worst, absf(v.y - col))
	assert_lte(worst, ShoreBand.COLLISION_CLAMP + ShoreBand.BAND_LIFT,
		"все вершины полосы ≤5 см от высоты коллизии (аналитика)")
	assert_lte(ShoreBand.COLLISION_CLAMP + ShoreBand.BAND_LIFT, 0.05,
		"труба к коллизии в пределах 5 см SPEC")
	# Честный raycast: физическая сцена с той же HeightMapShape3D,
	# что строит IslandView (та же карта высот без изменений).
	var root3d := Node3D.new()
	add_child_autofree(root3d)
	var body := StaticBody3D.new()
	root3d.add_child(body)
	var collision := CollisionShape3D.new()
	var shape := HeightMapShape3D.new()
	shape.map_width = IslandGen.POINTS
	shape.map_depth = IslandGen.POINTS
	shape.map_data = ART.heights
	collision.shape = shape
	body.add_child(collision)
	await get_tree().process_frame
	await get_tree().process_frame
	var space := root3d.get_world_3d().direct_space_state
	var worst_ray: float = 0.0
	var step: int = maxi(1, verts.size() / 200)
	var checked: int = 0
	for i: int in range(0, verts.size(), step):
		var v: Vector3 = verts[i]
		var query := PhysicsRayQueryParameters3D.create(
			Vector3(v.x, v.y + 1.0, v.z), Vector3(v.x, v.y - 1.0, v.z))
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		worst_ray = maxf(worst_ray, absf(v.y - float(hit.position.y)))
		checked += 1
	assert_gt(checked, 100, "raycast проверил достаточно вершин")
	assert_lte(worst_ray, 0.05,
		"отклонение полосы от коллизии (raycast) ≤ 5 см")


func test_band_cubic_matches_detail_ring_shader() -> void:
	# П15 9.1: бикубика полосы и детального кольца П14 — одна формула
	# (Catmull-Rom по 4×4 узлам с тем же прижимом TENSION_LIMIT), стык
	# кольца и полосы без шва; шейдер кольца не опускается ниже чанков.
	var ground := FileAccess.get_file_as_string(
		"res://assets/shaders/forest_ground.gdshader")
	assert_true(ground.contains("ring_catmull"),
		"кольцо считает Catmull-Rom бикубику")
	assert_almost_eq(_const_of(ground, "TENSION_LIMIT"),
		ShoreBand.TENSION_LIMIT, 0.0005,
		"прижим бикубики кольца — тот же лимит, что у полосы")
	assert_true(ground.contains("linear + 0.001"),
		"кольцо держится над чанковой высотой (не утопает)")
	# Сама бикубика: на целых узлах равна высоте карты (непрерывность
	# между клетками), между узлами отклоняется не дальше прижима.
	var heights: PackedFloat32Array = ART.heights
	for node: Vector2i in [Vector2i(10, 7), Vector2i(-40, 33),
			Vector2i(77, -5), Vector2i(0, 90)]:
		var at_node: float = ShoreBand.cubic_height(
			heights, float(node.x), float(node.y))
		assert_almost_eq(at_node, heights[(node.y + IslandGen.HALF)
			* IslandGen.POINTS + node.x + IslandGen.HALF], 0.0005,
			"бикубика на узле карты = высота узла (%s)" % node)
	for probe: Vector2 in [Vector2(10.4, 7.6), Vector2(-40.2, 33.8),
			Vector2(77.5, -5.3), Vector2(0.7, 90.1)]:
		var cubic: float = ShoreBand.cubic_height(heights, probe.x, probe.y)
		var tri: float = ShoreBand.tri_height(heights, probe.x, probe.y)
		assert_lte(absf(cubic - tri), ShoreBand.TENSION_LIMIT,
			"бикубика прижата к чанковой высоте (%s)" % probe)


# --- П15 5-6: каустика на дне и круги вокруг героя ---

func test_caustic_and_rings_only_in_full_shader() -> void:
	# П15 5-6: каустика и круги — эффекты полной версии шейдера
	# (HIGH/ULTRA): дешёвая версия без экранной выборки дна этих
	# параметров не имеет вовсе.
	assert_true(WATER_BU_CODE.contains("caustic_brightness"),
		"полный шейдер знает яркость каустики")
	assert_true(WATER_BU_CODE.contains("ripple_sources"),
		"полный шейдер принимает массив источников кругов")
	assert_false(WATER_CHEAP_CODE.contains("caustic_brightness"),
		"дешёвый шейдер без каустики")
	assert_false(WATER_CHEAP_CODE.contains("ripple_sources"),
		"дешёвый шейдер без кругов")


func test_caustic_fades_with_depth_and_light() -> void:
	# П15 5 + П15-ДОП блок 3: блики только на мелком (< 1.5 м — гашение
	# по толщине smoothstep'ом), пятно — произведение двух встречно
	# дрейфующих слоёв шума (туториал sample1 · sample2, прежний
	# pow(...,5) одного поля ушёл), и яркость следует за светом дна:
	# в тени и ночью дно тёмное — блик гаснет через его яркость
	# (bottom_luma), без отдельного множителя дня. Процедурная —
	# текстуры caustics_texture нет.
	assert_almost_eq(_const_of(WATER_BU_CODE, "CAUSTIC_MAX_DEPTH_M"),
		1.5, 0.001, "каустика живёт до 1.5 м глубины")
	assert_almost_eq(_const_of(WATER_BU_CODE, "CAUSTIC_SCALE"),
		1.3, 0.001, "масштаб слоёв каустики")
	var idx: int = WATER_BU_CODE.find("caustic_mask")
	assert_gt(idx, -1, "маска каустики считается в шейдере")
	var block: String = WATER_BU_CODE.substr(idx, 900)
	assert_true(block.contains("smoothstep"), "гашение с глубиной — smoothstep")
	assert_true(block.contains("(0.5 + 0.5 * snoise(cuv1))"),
		"первый слой каустики — шум 0..1")
	assert_true(block.contains("* (0.5 + 0.5 * snoise(cuv2))"),
		"пятно — произведение двух слоёв (туториал)")
	assert_true(block.contains("cuv2.y -= TIME * CAUSTIC_SPEED * 0.8;"),
		"слои дрейфуют встречно (по разным осям)")
	assert_true(block.contains("bottom_luma"),
		"блик пропорционален освещённости дна (тень и ночь гасят)")
	assert_false(WATER_BU_CODE.contains("pow(clamp(0.5 + 0.5 * cn"),
		"прежняя формула pow(...,5) ушла")
	assert_false(WATER_BU_CODE.contains("caustics_texture"),
		"текстуры каустики нет — процедурная")


func test_refraction_tutorial_depth_mask() -> void:
	# П15-ДОП блок 3: преломление по туториалу — смещение UV только
	# детальной частью нормали (детальная минус геометрическая: вдали,
	# куда нормаль сведена к геометрической, смещения нет само), сила
	# падает с дистанцией (ref_dist_factor) и гасится маской мелководья
	# ref_depth_mask (на сверхмелком дно не преломляется); защита от
	# предметов над водой — наша.
	var code := WATER_BU_CODE
	assert_true(code.contains(
			"vec2 normal_offset = nrm.xz - vertex_normal_world.xz;"),
		"смещение — только детальной частью нормали")
	assert_true(code.contains(
			"REFRACTION_FADE_M / max(0.1, surf_dist)"),
		"дистанционный спад силы — делением (туториал)")
	assert_true(code.contains("smoothstep(0.0, REF_DEPTH_M, thickness)"),
		"маска по толщине: сверхмелкое не преломляется")
	assert_between(_const_of(code, "REF_DEPTH_M"), 0.2, 1.0,
		"маска мелководья — десятки сантиметров")
	assert_gt(_const_of(code, "REFRACTION_FADE_M"), 0.0,
		"дистанция спада задана")
	assert_true(code.contains("if (-check_pos.z < surf_dist - 0.05)"),
		"защита выборки от предметов над водой — наша")
	assert_true(code.contains("refr_uv = SCREEN_UV;"),
		"сомнительная выборка заменяется прямой")


func test_volume_color_tints_bottom() -> void:
	# П15-ДОП блок 3: объёмный цвет туториала — volume = mix(мелководье,
	# глубина, depth_ratio) по толщине; им тонируется дно (apparent_
	# seabed = screen_color · volume), у кромки тонировка спадает (edge:
	# там вода прозрачная, П15 9.2), поглощение Бера — наше, по каналам.
	var code := WATER_BU_CODE
	assert_true(code.contains(
			"vec3 volume = mix(color_shallow.rgb, color_deep.rgb, depth_ratio);"),
		"объёмный цвет — mix мелководья и глубины по толщине")
	assert_true(code.contains("float depth_ratio = 1.0 - exp("),
		"доля глубины растёт с толщиной")
	assert_true(code.contains(
			"bottom * mix(vec3(1.0), volume, edge) * transmit"),
		"дно тонируется объёмным цветом, у кромки — нет")
	assert_true(code.contains("vec3 transmit = exp(-absorption * thickness);"),
		"поглощение Бера — наше, поканальное")
	assert_true(code.contains("vec3 scatter = volume;"),
		"рассеяние толщи — тот же объёмный цвет")


func test_rings_are_gaussian_rings_with_foam() -> void:
	# П15 6: кольца ряби — гауссовы пакеты (exp(-q²), без pow с
	# отрицательной базой), наклон — производная пакета по радиусу;
	# пена кругов подмешивается к береговой через max, не в EMISSION.
	var idx: int = WATER_BU_CODE.find("ripple_fx_amount",
		WATER_BU_CODE.find("void fragment"))
	assert_gt(idx, -1, "блок кругов есть во fragment")
	var block: String = WATER_BU_CODE.substr(idx, 1400)
	assert_true(block.contains("exp(-q1 * q1)"), "кольцо — гауссов пакет")
	assert_true(block.contains("RING_LIFE_SEC"), "кольцо живёт ограниченно")
	assert_true(block.contains("slope_r"), "кольцо наклоняет нормаль")
	assert_true(WATER_BU_CODE.contains(
			"foam_mask = max(foam_mask, rings_foam)"),
		"пена кругов входит в общую пену воды")


func test_water_area_ripple_slots_and_toggles() -> void:
	# П15 6-7: слоты источников (uniform-массив ≤ 4, время — TIME
	# шейдера), тумблеры F3 выключают и возвращают эффекты; яркость
	# каустики переживает выключенную галочку (ползунок П15 8.1).
	WorldMaterials.textured_headless = true
	var area := WaterArea.new()
	add_child_autofree(area)
	var material := area._surface_material(false) as ShaderMaterial
	assert_almost_eq(
		float(material.get_shader_parameter("ripple_fx_amount")),
		1.0, 0.001, "номинал: круги включены")
	assert_almost_eq(
		float(material.get_shader_parameter("caustic_brightness")),
		1.0, 0.001, "номинал: каустика включена")
	area.push_ripple(Vector2(3.0, 4.0), 0.8)
	var sources: PackedVector4Array = \
		material.get_shader_parameter("ripple_sources")
	var hit: int = 0
	for slot: Vector4 in sources:
		if slot.w > 0.001:
			hit += 1
			assert_almost_eq(slot.x, 3.0, 0.001, "слот помнит x круга")
			assert_almost_eq(slot.y, 4.0, 0.001, "слот помнит z круга")
			assert_gt(slot.z, 0.0, "время старта — TIME шейдера")
	assert_eq(hit, 1, "после первого круга живой слот один")
	# Пять пушей подряд — слотов всё равно 4 (замещается старейший).
	for i: int in 5:
		area.push_ripple(Vector2(float(i), 0.0), 0.8)
	assert_eq((material.get_shader_parameter("ripple_sources")
		as PackedVector4Array).size(), 4, "число слотов не растёт")
	# Тумблеры F3 (П15 7).
	area.set_ripples(false)
	assert_almost_eq(
		float(material.get_shader_parameter("ripple_fx_amount")),
		0.0, 0.001, "галочка выключила круги")
	area.set_ripples(true)
	assert_almost_eq(
		float(material.get_shader_parameter("ripple_fx_amount")),
		1.0, 0.001, "повторная галочка вернула круги")
	area.set_caustic_brightness(2.5)
	area.set_caustic(false)
	assert_almost_eq(
		float(material.get_shader_parameter("caustic_brightness")),
		0.0, 0.001, "галочка выключила каустику")
	area.set_caustic(true)
	assert_almost_eq(
		float(material.get_shader_parameter("caustic_brightness")),
		2.5, 0.001, "галочка вернула значение ползунка, а не номинал")
	WorldMaterials.textured_headless = false


func test_swimmer_pushes_ripples_by_step() -> void:
	# П15 6: круги пускаются по движению героя в воде — новый не чаще
	# шага RIPPLE_STEP_M; выключенный тумблер останавливает пуш.
	WorldMaterials.textured_headless = true
	var area := WaterArea.new()
	add_child_autofree(area)
	var material := area._surface_material(false) as ShaderMaterial
	var player := PLAYER.instantiate() as Player
	add_child_autofree(player)
	player.global_position = Vector3.ZERO
	area._local_swimmer = player
	area._last_ripple_xz = Vector2.ZERO
	area._physics_process(0.016)
	assert_eq(_live_ripple_slots(material), 0,
		"на месте круг не пускается повторно")
	player.global_position = Vector3(0.3, 0.0, 0.0)
	area._physics_process(0.016)
	assert_eq(_live_ripple_slots(material), 0,
		"ближе шага 0.55 м — круга нет")
	player.global_position = Vector3(0.6, 0.0, 0.0)
	area._physics_process(0.016)
	assert_eq(_live_ripple_slots(material), 1,
		"дальше шага — новый круг")
	area.set_ripples(false)
	player.global_position = Vector3(5.0, 0.0, 0.0)
	area._physics_process(0.016)
	assert_eq(_live_ripple_slots(material), 1,
		"выключенный тумблер останавливает круги")
	WorldMaterials.textured_headless = false


func _live_ripple_slots(material: ShaderMaterial) -> int:
	var sources: PackedVector4Array = \
		material.get_shader_parameter("ripple_sources")
	var count: int = 0
	for slot: Vector4 in sources:
		if slot.w > 0.001:
			count += 1
	return count


# --- П15 7-8: галочки F3 и вкладка «Вода» ---

func test_f3_caustic_and_rings_checkboxes() -> void:
	# П15 7: галочки «Каустика» и «Круги на воде» — только HIGH/ULTRA
	# (в дешёвом шейдере эффектов нет); снятая выключает эффект живой
	# зоны, повторная возвращает.
	var panel := DebugPanel.new()
	add_child_autofree(panel)
	panel.watch_graphics(
		Environment.new(), null, GraphicsQuality.Tier.HIGH)
	assert_true(panel._boxes.has(&"caustic"), "галочка «Каустика» есть")
	assert_true(panel._boxes.has(&"rings"), "галочка «Круги» есть")
	assert_true(panel._tier_effect_on(&"caustic"), "HIGH: каустика — уровень")
	assert_true(panel._tier_effect_on(&"rings"), "HIGH: круги — уровень")
	panel.watch_graphics(
		Environment.new(), null, GraphicsQuality.Tier.SIMPLE)
	assert_false(panel._tier_effect_on(&"caustic"),
		"SIMPLE: каустики в дешёвом шейдере нет")
	assert_false(panel._tier_effect_on(&"rings"),
		"SIMPLE: кругов в дешёвом шейдере нет")
	# Живое переключение: зона воды в группе water_surface (панель —
	# обратно на HIGH, возврат галочки возвращает эффект уровня).
	panel.watch_graphics(
		Environment.new(), null, GraphicsQuality.Tier.HIGH)
	WorldMaterials.textured_headless = true
	var area := WaterArea.new()
	add_child_autofree(area)
	var material := area._surface_material(false) as ShaderMaterial
	panel._boxes[&"caustic"].button_pressed = false
	assert_almost_eq(
		float(material.get_shader_parameter("caustic_brightness")),
		0.0, 0.001, "галочка выключила каустику")
	panel._boxes[&"caustic"].button_pressed = true
	assert_almost_eq(
		float(material.get_shader_parameter("caustic_brightness")),
		1.0, 0.001, "повторная галочка вернула каустику")
	panel._boxes[&"rings"].button_pressed = false
	assert_almost_eq(
		float(material.get_shader_parameter("ripple_fx_amount")),
		0.0, 0.001, "галочка выключила круги")
	panel._boxes[&"rings"].button_pressed = true
	assert_almost_eq(
		float(material.get_shader_parameter("ripple_fx_amount")),
		1.0, 0.001, "повторная галочка вернула круги")
	WorldMaterials.textured_headless = false


func test_water_tab_sliders_change_own_parameters() -> void:
	# П15 8.5 / П15-ДОП: каждый ползунок меняет свой параметр материала
	# воды (морская зона; база волн — константы моря, множители общие).
	WorldMaterials.textured_headless = true
	var area := WaterArea.new()
	add_child_autofree(area)
	var material := area._surface_material(false) as ShaderMaterial
	var panel := DebugPanel.new()
	add_child_autofree(panel)
	for def: Dictionary in panel.WATER_SLIDERS:
		var id: StringName = def["id"]
		var slider: HSlider = panel._sliders[id]
		slider.value = float(def["min"]) \
			+ (float(def["max"]) - float(def["min"])) * 0.7
		var applied: float = slider.value
		match id:
			&"abs":
				assert_true(_vec3_close(material.get_shader_parameter(
					"absorption"),
					WaterArea.TUT_SEA_ABSORPTION * applied),
					"поглощение = база моря пресета × ползунок")
			&"wave_height":
				assert_almost_eq(float(
					material.get_shader_parameter("sea_height")),
					WaterArea.SEA_WAVE_HEIGHT * applied, 0.0001,
					"высота волн = база моря × ползунок")
			&"wave_choppy":
				assert_almost_eq(float(
					material.get_shader_parameter("sea_choppiness")),
					WaterArea.SEA_WAVE_CHOPPY * applied, 0.0001,
					"острота гребней = база моря × ползунок")
			&"wave_speed":
				assert_almost_eq(float(
					material.get_shader_parameter("sea_speed")),
					WaterArea.SEA_WAVE_SPEED * applied, 0.0001,
					"скорость волн = база моря × ползунок")
			&"wave_freq":
				assert_almost_eq(float(
					material.get_shader_parameter("sea_freq")),
					WaterArea.SEA_WAVE_FREQ * applied, 0.0001,
					"частота волн = база моря × ползунок")
			&"ripple_strength":
				assert_almost_eq(float(
					material.get_shader_parameter("ripple_strength")),
					applied, 0.001, "сила ряби — ползунок")
			&"ripple_scale":
				assert_almost_eq(float(
					material.get_shader_parameter("ripple_scale")),
					applied, 0.001, "масштаб ряби — ползунок")
			&"refraction":
				assert_almost_eq(float(
					material.get_shader_parameter("refraction_amount")),
					applied, 0.001, "сила преломления — ползунок")
			&"foam_amount":
				assert_almost_eq(float(
					material.get_shader_parameter("foam_amount")),
					WaterArea.SEA_FOAM * applied, 0.001,
					"количество пены — база моря × ползунок")
			&"foam_width":
				assert_almost_eq(float(
					material.get_shader_parameter("foam_width")),
					applied, 0.001, "ширина пены — ползунок")
			&"foam_edge":
				assert_almost_eq(float(
					material.get_shader_parameter("foam_edge")),
					applied, 0.001, "сила кромки пены — ползунок")
			&"foam_bubbles":
				assert_almost_eq(float(
					material.get_shader_parameter("foam_bubbles")),
					applied, 0.001, "плотность пузырьков — ползунок")
			&"rough_near":
				assert_almost_eq(float(
					material.get_shader_parameter("roughness_near")),
					applied, 0.001, "шероховатость вблизи — ползунок")
			&"rough_far":
				assert_almost_eq(float(
					material.get_shader_parameter("roughness_far")),
					applied, 0.001, "шероховатость у горизонта — ползунок")
			&"caustic":
				assert_almost_eq(float(
					material.get_shader_parameter("caustic_brightness")),
					applied, 0.001, "яркость каустики — ползунок")
	WorldMaterials.textured_headless = false


func test_water_tab_colors_change_palette() -> void:
	# П15 8.1/8.5: цвета мелководья и глубины — раздельно озеро/море;
	# морской зоне пишут морские пикеры, озёрные её не трогают.
	WorldMaterials.textured_headless = true
	var area := WaterArea.new()
	add_child_autofree(area)
	var material := area._surface_material(false) as ShaderMaterial
	var panel := DebugPanel.new()
	add_child_autofree(panel)
	var deep_before: Color = material.get_shader_parameter("color_deep")
	var shallow_before: Color = \
		material.get_shader_parameter("color_shallow")
	# Программное присвоение color у ColorPickerButton сигнала не шлёт
	# (color_changed — из попапа пикера), поэтому связка проверяется
	# подключением, а обработчик зовётся как его зовёт пикер.
	assert_false(panel._pickers[&"sea_deep"]
		.color_changed.get_connections().is_empty(),
		"пикер глубины моря подключён к панели")
	panel._on_water_color_changed(Color(0.5, 0.1, 0.1), &"lake_deep")
	panel._on_water_color_changed(Color(0.6, 0.2, 0.2), &"lake_shallow")
	assert_eq(material.get_shader_parameter("color_deep"), deep_before,
		"пикер озера не трогает глубинный цвет моря")
	assert_eq(material.get_shader_parameter("color_shallow"),
		shallow_before, "пикер озера не трогает цвет мелководья моря")
	var new_deep := Color(0.05, 0.06, 0.09)
	var new_shallow := Color(0.2, 0.25, 0.3)
	panel._on_water_color_changed(new_deep, &"sea_deep")
	panel._on_water_color_changed(new_shallow, &"sea_shallow")
	assert_eq(material.get_shader_parameter("color_deep"), new_deep,
		"пикер моря пишет глубинный цвет")
	assert_eq(material.get_shader_parameter("color_shallow"), new_shallow,
		"пикер моря пишет цвет мелководья")
	WorldMaterials.textured_headless = false


func test_water_tab_reset_returns_defaults() -> void:
	# П15 8.2 / П15-ДОП блок 5: «Сбросить» возвращает номиналы всем
	# ползункам, цветам дефолтного пресета («Туториал») и самому
	# материалу воды — даже если перед этим был выбран «Born Unblessed».
	WorldMaterials.textured_headless = true
	var area := WaterArea.new()
	add_child_autofree(area)
	var material := area._surface_material(false) as ShaderMaterial
	var panel := DebugPanel.new()
	add_child_autofree(panel)
	for def: Dictionary in panel.WATER_SLIDERS:
		var slider: HSlider = panel._sliders[def["id"]]
		slider.value = float(def["max"])
	for def: Dictionary in panel.WATER_COLORS:
		panel._pickers[def["id"]].color = Color(0.9, 0.1, 0.9)
	panel._select_water_preset(WaterArea.WATER_PRESET_BU)
	panel._reset_water()
	for def: Dictionary in panel.WATER_SLIDERS:
		assert_almost_eq(panel._sliders[def["id"]].value,
			float(def["def"]), 0.0001,
			"«Сбросить» вернул ползунок %s" % def.get("const", def["id"]))
	var tutorial: Dictionary = \
		WaterArea.WATER_PRESETS[WaterArea.WATER_PRESET_DEFAULT]["colors"]
	for def: Dictionary in panel.WATER_COLORS:
		assert_eq(panel._pickers[def["id"]].color,
			tutorial[def["id"]],
			"«Сбросить» вернул цвет дефолтного пресета %s" % def["id"])
	assert_eq(panel._water_preset, WaterArea.WATER_PRESET_DEFAULT,
		"«Сбросить» вернул дефолтный пресет")
	assert_almost_eq(float(
		material.get_shader_parameter("refraction_amount")), 1.0, 0.001,
		"материал: преломление вернулось к номиналу")
	assert_almost_eq(float(
		material.get_shader_parameter("caustic_brightness")), 1.0, 0.001,
		"материал: каустика вернулась к номиналу")
	assert_true(_vec3_close(material.get_shader_parameter("absorption"),
		WaterArea.TUT_SEA_ABSORPTION), "материал: поглощение вернулось")
	assert_eq(material.get_shader_parameter("color_deep"),
		WaterArea.TUT_SEA_DEEP, "материал: глубинный цвет вернулся")
	WorldMaterials.textured_headless = false


func test_water_i18n_keys_present() -> void:
	# П15-ДОП блок 5: ключи пресета и новых ползунков пены есть в
	# strings_bu.csv с русским и английским текстом.
	var keys: Array[String] = ["BU_W_PRESET", "BU_W_PRESET_TUTORIAL",
		"BU_W_PRESET_BU", "BU_W_FOAM_EDGE", "BU_W_FOAM_BUBBLES"]
	var file := FileAccess.open(
		"res://i18n/strings_bu.csv", FileAccess.READ)
	assert_not_null(file, "файл строк есть")
	if file == null:
		return
	file.get_csv_line()
	var csv: Dictionary = {}
	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.size() >= 3 and line[0] != "":
			csv[line[0]] = line
	file.close()
	for key: String in keys:
		assert_true(csv.has(key), "ключ %s есть в CSV" % key)
		if csv.has(key):
			assert_false((csv[key] as PackedStringArray)[1].is_empty(),
				"%s: русский текст есть" % key)
			assert_false((csv[key] as PackedStringArray)[2].is_empty(),
				"%s: английский текст есть" % key)


func test_water_presets_switch_colors_and_absorption() -> void:
	# П15-ДОП блок 5: дефолт — «Туториал» (бирюзовый по туториалу);
	# пресет = 4 цвета + поглощение озера и моря; переключение меняет
	# базы зоны и материалы, построенные позже поверхности берут его же;
	# ночной спад update_sky живёт от баз пресета.
	WorldMaterials.textured_headless = true
	assert_eq(WaterArea.water_preset(), WaterArea.WATER_PRESET_TUTORIAL,
		"по умолчанию — пресет «Туториал»")
	var area := WaterArea.new()
	add_child_autofree(area)
	var material := area._surface_material(false) as ShaderMaterial
	assert_eq(material.get_shader_parameter("color_deep"),
		WaterArea.TUT_SEA_DEEP, "дефолт: глубинный цвет — бирюзовый")
	assert_true(_vec3_close(material.get_shader_parameter("absorption"),
		WaterArea.TUT_SEA_ABSORPTION), "дефолт: поглощение — туториала")
	# Переключение на «Born Unblessed»: базы и материал живой зоны.
	WaterArea.set_water_preset(WaterArea.WATER_PRESET_BU)
	area.apply_water_preset()
	assert_eq(material.get_shader_parameter("color_deep"),
		WaterArea.SEA_DEEP, "BU: глубинный цвет — тёмная сталь")
	assert_true(_vec3_close(material.get_shader_parameter("absorption"),
		WaterArea.SEA_ABSORPTION), "BU: поглощение — плотное")
	# Построенная после переключения поверхность — сразу из пресета.
	var lake := WaterArea.new()
	add_child_autofree(lake)
	var lake_material := lake._surface_material(true) as ShaderMaterial
	assert_eq(lake_material.get_shader_parameter("color_shallow"),
		WaterArea.LAKE_SHALLOW, "озеро после переключения — торфяное")
	# Ночной спад от баз пресета: цвета гаснут, не вспыхивают.
	area.update_sky(Color(0.1, 0.1, 0.12), Color(0.05, 0.05, 0.08),
		Vector3.DOWN, Color.BLACK)
	assert_lt((material.get_shader_parameter("color_deep") as Color)
		.get_luminance(), WaterArea.SEA_DEEP.get_luminance(),
		"ночь гасит глубинный цвет пресета BU")
	# Неизвестный идентификатор пресет не меняет.
	WaterArea.set_water_preset(&"nope")
	assert_eq(WaterArea.water_preset(), WaterArea.WATER_PRESET_BU,
		"неизвестный пресет отклонён")
	# Вернуть дефолт — остальные тесты рассчитывают на «Туториал».
	WaterArea.set_water_preset(WaterArea.WATER_PRESET_TUTORIAL)
	WorldMaterials.textured_headless = false


func test_water_tab_preset_switch() -> void:
	# П15-ДОП блок 5: переключатель пресетов во вкладке «Вода» — обе
	# кнопки, выбор меняет зоны группы water_surface и пикеры панели;
	# ползунки множат базы активного пресета.
	WorldMaterials.textured_headless = true
	var area := WaterArea.new()
	add_child_autofree(area)
	var material := area._surface_material(false) as ShaderMaterial
	var panel := DebugPanel.new()
	add_child_autofree(panel)
	for id: StringName in [WaterArea.WATER_PRESET_TUTORIAL,
			WaterArea.WATER_PRESET_BU]:
		assert_true(panel._preset_buttons.has(id),
			"кнопка пресета %s есть" % id)
	assert_true(panel._preset_buttons[WaterArea.WATER_PRESET_TUTORIAL]
		.button_pressed, "по умолчанию нажата кнопка «Туториал»")
	panel._select_water_preset(WaterArea.WATER_PRESET_BU)
	assert_eq(panel._water_preset, WaterArea.WATER_PRESET_BU,
		"панель помнит активный пресет")
	assert_eq(material.get_shader_parameter("color_deep"),
		WaterArea.SEA_DEEP, "зона получила палитру BU")
	assert_eq(panel._pickers[&"sea_deep"].color, WaterArea.SEA_DEEP,
		"пикер глубины моря — на значении пресета BU")
	# Ползунок поглощения множит базу активного пресета.
	panel._sliders[&"abs"].value = 2.0
	assert_true(_vec3_close(material.get_shader_parameter("absorption"),
		WaterArea.SEA_ABSORPTION * 2.0),
		"поглощение = база BU × ползунок")
	WaterArea.set_water_preset(WaterArea.WATER_PRESET_TUTORIAL)
	WorldMaterials.textured_headless = false


func test_water_tab_copy_contains_all() -> void:
	# П15 8.3 / П15-ДОП: текст «Скопировать значения» — константы
	# WaterArea со всеми параметрами: цвета и поглощение — именами
	# активного пресета (TUT_* / LAKE_*-SEA_*), волновые базы — с
	# применённым множителем ползунка; числа вставляются в water_area.gd.
	var panel := DebugPanel.new()
	add_child_autofree(panel)
	var text := panel.build_water_values_text()
	for const_name: String in [
		"TUT_LAKE_DEEP", "TUT_LAKE_SHALLOW", "TUT_SEA_DEEP",
		"TUT_SEA_SHALLOW", "TUT_LAKE_ABSORPTION", "TUT_SEA_ABSORPTION",
		"ABSORPTION_MULT", "SEA_WAVE_HEIGHT", "LAKE_WAVE_HEIGHT",
		"SEA_WAVE_CHOPPY", "LAKE_WAVE_CHOPPY",
		"SEA_WAVE_SPEED", "LAKE_WAVE_SPEED", "SEA_WAVE_FREQ",
		"LAKE_WAVE_FREQ",
		"RIPPLE_STRENGTH_MULT", "RIPPLE_SCALE_MULT", "REFRACTION_MULT",
		"FOAM_MULT", "FOAM_WIDTH", "FOAM_EDGE", "FOAM_BUBBLES",
		"ROUGHNESS_NEAR", "ROUGHNESS_FAR",
		"CAUSTIC_BRIGHTNESS",
	]:
		assert_true(text.contains("const %s:" % const_name),
			"в тексте есть константа %s" % const_name)
	# Множители волн в текст не входят — вставляются сами базы.
	assert_false(text.contains("WAVE_HEIGHT_MULT"),
		"множитель высоты печатается базой, не множителем")
	# Числа — те же, что в константах WaterArea.
	assert_true(text.contains("const FOAM_WIDTH: float = 0.06"),
		"ширина пены — 0.06")
	assert_true(text.contains("const FOAM_EDGE: float = 0.8"),
		"сила кромки — 0.8")
	assert_true(text.contains("const FOAM_BUBBLES: float = 0.8"),
		"плотность пузырьков — 0.8")
	assert_true(text.contains("const ROUGHNESS_NEAR: float = 0.03"),
		"шероховатость вблизи — 0.03")
	assert_true(text.contains("const CAUSTIC_BRIGHTNESS: float = 1.0"),
		"яркость каустики — 1.0")
	assert_true(text.contains("const SEA_WAVE_FREQ: float = 0.08"),
		"частота морских волн — 0.08")
	assert_true(text.contains("const TUT_LAKE_DEEP: Color = "
		+ "Color(0.02, 0.22, 0.13, 1.0)"),
		"палитра озера — числами пресета")
	assert_true(text.contains(
		"const TUT_SEA_ABSORPTION: Vector3 = Vector3(0.35, 0.1, 0.05)"),
		"база поглощения моря — числами пресета")
	# Пресет BU печатает свои имена констант.
	panel._select_water_preset(WaterArea.WATER_PRESET_BU)
	assert_true(panel.build_water_values_text().contains(
		"const LAKE_DEEP: Color = Color(0.016, 0.035, 0.028, 1.0)"),
		"пресет BU печатает константы LAKE_*")
	assert_true(panel.build_water_values_text().contains(
		"const SEA_ABSORPTION: Vector3 = Vector3(1.05, 0.5, 0.34)"),
		"пресет BU печатает поглощение SEA_*")
	# Подвинутый ползунок попадает в текст своим числом.
	panel._select_water_preset(WaterArea.WATER_PRESET_TUTORIAL)
	panel._sliders[&"caustic"].value = 2.4
	assert_true(panel.build_water_values_text().contains(
		"const CAUSTIC_BRIGHTNESS: float = 2.4"),
		"текущее значение ползунка печатается")
	# Множитель поглощения уезжает в печатаемые базы.
	panel._sliders[&"abs"].value = 2.0
	assert_true(panel.build_water_values_text().contains(
		"const TUT_SEA_ABSORPTION: Vector3 = Vector3(0.7, 0.2, 0.1)"),
		"база поглощения печатается с множителем ползунка")


# --- П15-ДОП блок 7: приёмка ---

func test_shader_compiles_on_all_tiers() -> void:
	# П15-ДОП блок 7: шейдер воды компилируется на каждом уровне
	# графики. GPU-компиляции в headless нет, но движок разбирает код
	# шейдера целиком и при синтаксической ошибке список uniform'ов
	# пуст — код ставится в свежий Shader, разбор выполняется здесь,
	# а не берётся кэшем ресурса. SIMPLE/NORMAL — дешёвый шейдер,
	# HIGH/ULTRA — полный.
	for row: Array in [
		["SIMPLE", GraphicsQuality.Tier.SIMPLE, WaterArea.WATER_BU_CHEAP],
		["NORMAL", GraphicsQuality.Tier.NORMAL, WaterArea.WATER_BU_CHEAP],
		["HIGH", GraphicsQuality.Tier.HIGH, WaterArea.WATER_BU],
		["ULTRA", GraphicsQuality.Tier.ULTRA, WaterArea.WATER_BU],
	]:
		var tier_name: String = row[0]
		var shader: Shader = row[2]
		assert_eq(WaterArea.shader_for_tier(row[1]), shader,
			"%s: тир выбирает %s" % [tier_name,
				shader.resource_path.get_file()])
		var fresh := Shader.new()
		fresh.code = shader.code
		var uniforms: Array = fresh.get_shader_uniform_list()
		assert_gt(uniforms.size(), 20,
			"%s: шейдер разбирается (uniform'ов > 20)" % tier_name)
		# Общий набор волн и палитры — в обоих шейдерах.
		for key: String in ["sea_height", "sea_choppiness",
				"sea_speed", "sea_freq", "color_deep", "color_shallow",
				"absorption", "roughness_near", "roughness_far"]:
			assert_true(_has_uniform(uniforms, key),
				"%s: uniform %s на месте" % [tier_name, key])
	# Экранная выборка — только у полной версии (дешёвая без
	# hint_screen_texture, SPEC П14 4.7). Проверяется кодом: движок
	# не включает hint_screen_texture/hint_depth_texture в uniform-лист.
	assert_true(WATER_BU_CODE.contains("hint_screen_texture"),
		"полный: экранная текстура есть")
	assert_false(WATER_CHEAP_CODE.contains("hint_screen_texture"),
		"дешёвый: без экранной выборки")


static func _has_uniform(uniforms: Array, uniform_name: String) -> bool:
	for entry: Dictionary in uniforms:
		if entry.get("name", "") == uniform_name:
			return true
	return false


static func _vec3_close(got: Variant, expected: Vector3) -> bool:
	if got is not Vector3:
		return false
	var v: Vector3 = got
	return is_equal_approx(v.x, expected.x) \
		and is_equal_approx(v.y, expected.y) \
		and is_equal_approx(v.z, expected.z)
