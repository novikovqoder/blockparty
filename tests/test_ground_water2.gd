# Тесты П14 «Земля и вода, вторая итерация»: реальный масштаб тайлов
# и нейтральные тинты (блок 1), стандартное PBR-освещение и AO-выход
# (блок 2), детальное кольцо/POM/мелочь (блок 3), свой шейдер воды
# вместо Boujie (блок 4), галочки F3 (блок 5). Сервер — без рендера:
# шейдерное поведение проверяется материалом (uniform по уровням)
# и исходником шейдера, как test_ground_water / test_texture_audit.
extends GutTest

const ART: IslandArt = preload("res://gameplay/world/island_art.res")
const GROUND_SHADER: Shader = preload(
	"res://assets/shaders/forest_ground.gdshader")


# --- П14 блок 1: масштаб и цвет ---

func test_layer_tiles_real_world() -> void:
	# П14 1.1: тайл каждого слоя ≤ 5 м (реальные размеры Poly Haven:
	# 2 / 2 / 2.7 / 2.3 / 2 / 2), константы доезжают в материал.
	var pairs: Dictionary[String, float] = {
		"tile_m_litter": ForestGround.TILE_M_LITTER,
		"tile_m_grass": ForestGround.TILE_M_GRASS,
		"tile_m_rock": ForestGround.TILE_M_ROCK,
		"tile_m_mud": ForestGround.TILE_M_MUD,
		"tile_m_moss": ForestGround.TILE_M_MOSS,
		"tile_m_gravel": ForestGround.TILE_M_GRAVEL,
	}
	var material := ForestGround.make_material(ART, GraphicsQuality.Tier.HIGH)
	for key: String in pairs:
		var value: float = pairs[key]
		assert_between(value, 1.0, 5.0,
			"%s: реальный размер тайла 1–5 м (%.1f)" % [key, value])
		assert_almost_eq(
			float(material.get_shader_parameter(key)), value, 0.0001,
			"%s: константа в материале" % key)
	# Прежний единый тайл 30 м («картинка, натянутая на поверхность»)
	# исчез из шейдера.
	assert_false(GROUND_SHADER.code.contains("uniform float tile_m ="),
		"единого tile_m больше нет — у каждого слоя свой")
	assert_false(GROUND_SHADER.code.contains("= 30.0"),
		"тайл 30 м исчез")


func test_tints_neutral_no_burn() -> void:
	# П14 1.3: тинты нейтральные ≈ белые, без каналов > 1.0 (прежде
	# TINT_LITTER (0.83, 0.84, 1.07) синил землю), tint_mix ≈ 0.05–0.15 —
	# цвет даёт фотоскан.
	for pair: Array in [
		["litter", ForestGround.TINT_LITTER],
		["grass", ForestGround.TINT_GRASS],
		["rock", ForestGround.TINT_ROCK],
		["mud", ForestGround.TINT_MUD],
		["moss", ForestGround.TINT_MOSS],
		["gravel", ForestGround.TINT_GRAVEL],
	]:
		var tint: Color = pair[1]
		for channel: float in [tint.r, tint.g, tint.b]:
			assert_lte(channel, 1.0,
				"тинт %s: канал ≤ 1.0" % pair[0])
			assert_gte(channel, 0.3,
				"тинт %s: нейтральный, не чёрный" % pair[0])
	assert_between(ForestGround.TINT_MIX, 0.05, 0.15,
		"tint_mix ≈ 0.05–0.15 (цвет даёт фотоскан)")
	var material := ForestGround.make_material(ART, GraphicsQuality.Tier.HIGH)
	assert_almost_eq(
		float(material.get_shader_parameter("tint_mix")),
		ForestGround.TINT_MIX, 0.0001, "tint_mix в материале")
	# Дефолты шейдера — те же нейтральные значения (проверка исходником,
	# без рендера): нет сгорающих каналов в uniform-строках тинтов.
	var text := GROUND_SHADER.code
	for uniform_name: String in [
		"litter_tint", "grass_tint", "rock_tint",
		"mud_tint", "moss_tint", "gravel_tint",
	]:
		var regex := RegEx.new()
		regex.compile("uniform vec3 %s[^=]*= vec3\\(([\\d., ]+)\\)" % uniform_name)
		var found := regex.search(text)
		assert_not_null(found, "uniform %s найден" % uniform_name)
		if found == null:
			continue
		for part: String in found.get_string(1).split(","):
			assert_lte(float(part), 1.0,
				"%s: дефолт без канала > 1.0" % uniform_name)


func test_macro_second_scale_against_repeats() -> void:
	# П14 1.2: второй крупный масштаб того же слоя ×4–6, подмешивается
	# с 15 до 40 м — вблизи мелкая фактура, вдали нет сетки повторов.
	assert_between(ForestGround.MACRO_SCALE, 4.0, 6.0,
		"макро-масштаб ×4–6")
	assert_between(ForestGround.MACRO_NEAR, 15.0, 40.0,
		"макро подмешивается с 15–40 м")
	assert_between(ForestGround.MACRO_FAR, 15.0, 60.0,
		"макро полностью к 40–60 м")
	assert_lt(ForestGround.MACRO_NEAR, ForestGround.MACRO_FAR,
		"макро: near < far")
	var material := ForestGround.make_material(ART, GraphicsQuality.Tier.HIGH)
	assert_almost_eq(float(material.get_shader_parameter("macro_scale")),
		ForestGround.MACRO_SCALE, 0.0001, "macro_scale в материале")
	assert_true(
		GROUND_SHADER.code.contains("smoothstep(macro_near, macro_far"),
		"шейдер подмешивает макро-масштаб по дистанции")
	# Бывший «детальный» масштаб 6 м убран: базовый тайл теперь сам мелкий.
	assert_false(GROUND_SHADER.code.contains("detail_tile_m"),
		"детальный масштаб 6 м исчез (тайл слоя уже 2 м)")


# --- П14 блок 3: детальная сетка, POM, берег, мелочь ---

func test_detail_ring_steps_by_tier() -> void:
	# П14 3.1: кольцо только на HIGH/ULTRA; шаг 0.25 м HIGH / 0.125 м
	# ULTRA, радиус ~16 / ~24 м; у ULTRA сетка вдвое плотнее.
	assert_false(TerrainDetail.is_ring_enabled(GraphicsQuality.Tier.SIMPLE),
		"SIMPLE — без кольца")
	assert_false(TerrainDetail.is_ring_enabled(GraphicsQuality.Tier.NORMAL),
		"NORMAL — без кольца")
	assert_true(TerrainDetail.is_ring_enabled(GraphicsQuality.Tier.HIGH),
		"HIGH — с кольцом")
	assert_true(TerrainDetail.is_ring_enabled(GraphicsQuality.Tier.ULTRA),
		"ULTRA — с кольцом")
	assert_almost_eq(TerrainDetail.STEP_HIGH, 0.25, 0.001,
		"шаг HIGH 0.25 м")
	assert_almost_eq(TerrainDetail.STEP_ULTRA, 0.125, 0.001,
		"шаг ULTRA 0.125 м")
	# П16 п. 3: радиус HIGH уменьшен 16 → 12 м (встройке хватало 16,
	# но 12 вчетверо дешевле по вершинам).
	assert_between(TerrainDetail.RADIUS_HIGH, 10.0, 14.0, "радиус HIGH 12 м (П16)")
	assert_between(TerrainDetail.RADIUS_ULTRA, 22.0, 26.0, "радиус ULTRA ~24 м")
	assert_almost_eq(
		TerrainDetail.step_for_tier(GraphicsQuality.Tier.HIGH), 0.25, 0.001)
	assert_almost_eq(
		TerrainDetail.step_for_tier(GraphicsQuality.Tier.ULTRA), 0.125, 0.001)
	assert_almost_eq(
		TerrainDetail.radius_for_tier(GraphicsQuality.Tier.HIGH), 12.0, 0.001)
	assert_almost_eq(
		TerrainDetail.radius_for_tier(GraphicsQuality.Tier.ULTRA), 24.0, 0.001)


func test_ring_mesh_is_flat_grid() -> void:
	# Сетка кольца плоская (высоту ставит шейдер), покрывает квадрат
	# радиуса с шагом, индексы — два треугольника на квад.
	var mesh := TerrainDetail.build_mesh(0.25, 16.0)
	var surface := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = surface[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = surface[Mesh.ARRAY_INDEX]
	assert_eq(vertices.size(), 129 * 129, "вершины 129 × 129")
	assert_eq(indices.size(), 128 * 128 * 6, "треугольники 128 × 128 × 2")
	for vertex: Vector3 in vertices:
		assert_almost_eq(vertex.y, 0.0, 0.0001, "сетка плоская (y = 0)")
		assert_lte(absf(vertex.x), 16.0 + 0.001, "в пределах радиуса")
		assert_lte(absf(vertex.z), 16.0 + 0.001, "в пределах радиуса")


func test_ring_displacement_amplitudes() -> void:
	# П14 3.1: амплитуды слоёв — подстилка/мох/гравий ±3–5 см, грязь
	# 8–10 см, скала до 15 см; те же значения — в константах шейдера
	# (общая глубина POM и кольца).
	assert_between(TerrainDetail.AMP_LITTER, 0.03, 0.05, "подстилка 3–5 см")
	assert_between(TerrainDetail.AMP_MOSS, 0.02, 0.05, "мох 2–5 см")
	assert_between(TerrainDetail.AMP_GRAVEL, 0.03, 0.05, "гравий 3–5 см")
	assert_between(TerrainDetail.AMP_MUD, 0.08, 0.10, "грязь 8–10 см")
	assert_between(TerrainDetail.AMP_ROCK, 0.12, 0.15, "скала до 15 см")
	var text := GROUND_SHADER.code
	for pair: Array in [
		["AMP_LITTER_C", TerrainDetail.AMP_LITTER],
		["AMP_ROCK_C", TerrainDetail.AMP_ROCK],
		["AMP_MUD_C", TerrainDetail.AMP_MUD],
		["AMP_MOSS_C", TerrainDetail.AMP_MOSS],
		["AMP_GRAVEL_C", TerrainDetail.AMP_GRAVEL],
	]:
		assert_almost_eq(_extract_const(text, String(pair[0])),
			float(pair[1]), 0.0001,
			"%s шейдера = амплитуде кольца" % pair[0])


func test_ring_displacement_mean_near_zero() -> void:
	# П14 3.1: смещение центрировано средним канала высоты слоя —
	# средняя высота кольца над чанками ≈ 0 (±1 см), коллизия не
	# меняется, ступни не проваливаются. Проба по сетке точек острова.
	var weights := ForestGround._weights_image(ART)
	var orm_images := TerrainDetail.orm_images()
	var means := TerrainDetail.orm_means()
	var sum := 0.0
	var count := 0
	for wz: int in range(-100, 101, 8):
		for wx: int in range(-100, 101, 8):
			sum += TerrainDetail.displacement_at(
				ART, weights, orm_images, means, float(wx), float(wz))
			count += 1
	var mean: float = sum / float(count)
	assert_between(mean, -0.01, 0.01,
		"среднее смещение ≈ 0 ±1 см (факт %.4f м)" % mean)


func test_ring_uses_height_texture_and_fade() -> void:
	# Материал кольца: detail_ring включен, карта высот задана (та же
	# сетка 257 × 257, что коллизия), средние ORM и радиус по уровню;
	# у материала чанков detail_ring выключен, но height_tex задан
	# (сэмплер не пустой).
	var base := ForestGround.make_material(ART, GraphicsQuality.Tier.HIGH)
	assert_false(bool(base.get_shader_parameter("detail_ring")),
		"чанки — без кольца")
	assert_not_null(base.get_shader_parameter("height_tex"),
		"height_tex задан и у чанков (сэмплер не пустой)")
	var ring := TerrainDetail.make_material(base, ART, GraphicsQuality.Tier.ULTRA)
	assert_true(bool(ring.get_shader_parameter("detail_ring")),
		"кольцо — detail_ring")
	var heights: Image = (ring.get_shader_parameter("height_tex") as ImageTexture).get_image()
	assert_eq(heights.get_width(), IslandGen.POINTS, "ширина карты высот")
	assert_eq(heights.get_height(), IslandGen.POINTS, "высота карты высот")
	assert_almost_eq(float(ring.get_shader_parameter("ring_radius")),
		TerrainDetail.RADIUS_ULTRA, 0.001, "радиус кольца ULTRA")
	# Гашение к кромке: смещение и подъём исчезают у края (константы).
	assert_between(_extract_const(GROUND_SHADER.code, "RING_EDGE_FADE"),
		1.0, 3.0, "полоса гашения смещения у кромки")
	assert_between(_extract_const(GROUND_SHADER.code, "RING_LIFT_C"),
		0.002, 0.01, "подъём кольца — миллиметры против z-fighting")
	# Хеш высот не меняется: кольцо — рантайм-оверлей, генератор не тронут.
	assert_eq(IslandGen.island_hash(IslandGen.generate()), 941246210,
		"хеш острова не изменился")


func test_pom_steps_by_tier() -> void:
	# П14 3.2: марш POM 8 шагов HIGH / 16 ULTRA, глубина — амплитуда
	# слоя; parallax_scale — выключатель (master = parallax_scale/0.06).
	assert_eq(ForestGround.pom_steps_for_tier(GraphicsQuality.Tier.HIGH), 8,
		"HIGH — 8 шагов")
	assert_eq(ForestGround.pom_steps_for_tier(GraphicsQuality.Tier.ULTRA), 16,
		"ULTRA — 16 шагов")
	var material := ForestGround.make_material(ART, GraphicsQuality.Tier.ULTRA)
	assert_almost_eq(float(material.get_shader_parameter("pom_steps")),
		16.0, 0.001, "pom_steps в материале ULTRA")
	var high := ForestGround.make_material(ART, GraphicsQuality.Tier.HIGH)
	assert_almost_eq(float(high.get_shader_parameter("pom_steps")),
		8.0, 0.001, "pom_steps в материале HIGH")
	assert_true(GROUND_SHADER.code.contains("pom_march"),
		"шейдер марширует по карте высот слоя")
	assert_true(GROUND_SHADER.code.contains("min(parallax_scale / 0.06, 1.0)"),
		"параллакс F3 гасит глубину POM целиком")


func test_shore_band_wet_strip() -> void:
	# П14 3.4: мокрая полоса берега по высоте над уровнем воды (без
	# ломаной грани — smoothstep), уровень — тот же, что у моря/озера.
	assert_almost_eq(float(
		ForestGround.make_material(ART, GraphicsQuality.Tier.HIGH)
			.get_shader_parameter("shore_level")),
		IslandGen.SEA_LEVEL, 0.0001, "shore_level = уровень воды")
	var text := GROUND_SHADER.code
	assert_almost_eq(_extract_uniform(text, "shore_level"), -0.15, 0.0001,
		"дефолт шейдера — уровень моря")
	assert_between(_extract_const(text, "SHORE_BAND"), 0.3, 0.9,
		"полоса берега 30–90 см над водой")
	assert_between(_extract_const(text, "SHORE_DARKEN"), 0.45, 0.8,
		"мокрый берег темнее")
	assert_true(text.contains("smoothstep(\n\t\t0.03, SHORE_BAND"),
		"край полосы — smoothstep от кромки воды")
	assert_true(text.contains("mix(ROUGHNESS, 0.32, shore_w"),
		"мокрая полоса глаже (roughness)")


func test_ground_clutter_ring_around_player() -> void:
	# П14 3.3: мелочь — кольцо 15–25 м вокруг игрока, детерминирована
	# по мировым клеткам (свой seed на клетку), HIGH = ½ ULTRA,
	# тени только ULTRA, коллизии нет.
	assert_between(GroundClutter.RADIUS, 15.0, 25.0, "радиус кольца мелочи")
	assert_false(GroundClutter.is_clutter_enabled(GraphicsQuality.Tier.NORMAL),
		"NORMAL — без мелочи")
	assert_true(GroundClutter.is_clutter_enabled(GraphicsQuality.Tier.HIGH),
		"HIGH — с мелочью")
	assert_almost_eq(
		GroundClutter.density_for_tier(GraphicsQuality.Tier.HIGH) \
			/ GroundClutter.density_for_tier(GraphicsQuality.Tier.ULTRA),
		0.5, 0.001, "плотность HIGH = ½ ULTRA")
	var center := Vector2(20.0, 30.0)
	var ultra := GroundClutter.scatter(ART, GraphicsQuality.Tier.ULTRA, center)
	var ultra_repeat := GroundClutter.scatter(
		ART, GraphicsQuality.Tier.ULTRA, center)
	var total := 0
	for type: String in ultra:
		total += (ultra[type]["transforms"] as Array).size()
		# Цвета инстансов доезжают вместе с трансформами (регресс COW:
		# append через as-каст уходил в копию, apply_clutter падал на
		# пустом PackedColorArray).
		assert_eq((ultra[type]["colors"] as PackedColorArray).size(),
			(ultra[type]["transforms"] as Array).size(),
			"каждому инстансу — свой цвет (%s)" % type)
		var again: Array = ultra_repeat[type]["transforms"]
		var first: Array = ultra[type]["transforms"]
		assert_eq(again.size(), first.size(),
			"повторная раскладка — то же число (%s)" % type)
		for i: int in mini(first.size(), again.size()):
			assert_true(
				(first[i] as Transform3D).origin.is_equal_approx(
					(again[i] as Transform3D).origin),
				"детерминизм позиций по мировым клеткам (%s)" % type)
	assert_gt(total, 100, "в кольце 20 м есть мелочь")
	# HIGH — примерно половина инстансов той же области (статистика
	# бросков по клеткам с плотностью ½).
	var high := GroundClutter.scatter(ART, GraphicsQuality.Tier.HIGH, center)
	var total_high := 0
	for type: String in high:
		total_high += (high[type]["transforms"] as Array).size()
	assert_between(
		float(total_high) / float(maxi(total, 1)), 0.3, 0.7,
		"HIGH ≈ ½ ULTRA (факт %.2f)" % (float(total_high) / float(total)))
	# Тени и видимость нод: ULTRA — с тенями, HIGH — без; мелочь
	# дальше радиуса не ставится.
	var nodes := GroundClutter.make_nodes(GraphicsQuality.Tier.HIGH)
	for type: String in nodes:
		var node: MultiMeshInstance3D = nodes[type]
		assert_eq(node.cast_shadow,
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"HIGH — тени мелочи выключены (%s)" % type)
	var nodes_ultra := GroundClutter.make_nodes(GraphicsQuality.Tier.ULTRA)
	for type: String in nodes_ultra:
		var node: MultiMeshInstance3D = nodes_ultra[type]
		assert_eq(node.cast_shadow,
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
			"ULTRA — мелочь отбрасывает тень (%s)" % type)
	for type: String in ultra:
		for xf: Transform3D in ultra[type]["transforms"]:
			assert_lte(
				Vector2(xf.origin.x, xf.origin.z).distance_to(center),
				GroundClutter.RADIUS + 0.6,
				"мелочь не дальше радиуса кольца")


func test_ground_clutter_blocks_zones() -> void:
	# П14 3.3: мелочь не ставится на пляже/воде, Площади и у построек —
	# те же запретные зоны, что у наполнения. Центр — Лес в 42 м от
	# Площади: ближний край кольца (20 м) захватывает блокируемые
	# клетки Plaza (24 м мягкого края) — проверка не пустая и не холостая.
	var center := Vector2(-30.0, -30.0)
	var scattered := GroundClutter.scatter(ART, GraphicsQuality.Tier.ULTRA, center)
	var total := 0
	for type: String in scattered:
		total += (scattered[type]["transforms"] as Array).size()
	assert_gt(total, 50, "в чаще Леса вокруг есть мелочь (проба не пустая)")
	for type: String in scattered:
		for xf: Transform3D in scattered[type]["transforms"]:
			var pos := Vector2(xf.origin.x, xf.origin.z)
			assert_lt(
				ForestGround._plaza_weight(pos.x, pos.y), 0.06,
				"мелочи нет на Площади (%s)" % type)
			assert_false(IslandGen.on_village_pad(pos),
				"мелочи нет во дворах построек (%s)" % type)
			assert_gte(pos.distance_to(GroundClutter.RUIN_CENTER),
				GroundClutter.RUIN_CLEAR,
				"мелочи нет на террасе руин (%s)" % type)


# --- П14 блок 4: свой шейдер воды вместо Boujie ---

func test_water_new_shader_on_all_surfaces() -> void:
	# П14 4: шейдер воды — water_bu (полный на HIGH/ULTRA) или
	# water_bu_cheap (SIMPLE/NORMAL); копий Boujie в материалах нет,
	# текстур аддона шейдер не читает вовсе.
	WorldMaterials.textured_headless = true
	var area := WaterArea.new()
	add_child_autofree(area)
	for pair: Array in [["озеро", true], ["море", false]]:
		var material := area._surface_material(pair[1]) as ShaderMaterial
		assert_true(material.shader == WaterArea.WATER_BU
			or material.shader == WaterArea.WATER_BU_CHEAP,
			"%s: новый шейдер water_bu*" % pair[0])
	WorldMaterials.textured_headless = false
	var area_text := FileAccess.get_file_as_string(
		"res://gameplay/world/water_area.gd")
	assert_false(area_text.contains("addons/boujie_water_shader"),
		"WaterArea не грузит текстуры Boujie")
	assert_true(WaterArea.WATER_BU.code.contains("hint_screen_texture"),
		"полная версия читает экран")
	assert_true(WaterArea.WATER_BU.code.contains("hint_depth_texture"),
		"полная версия читает буфер глубины")
	assert_false(
		WaterArea.WATER_BU_CHEAP.code.contains("hint_screen_texture"),
		"дешёвая версия без экранной выборки (4.7)")
	assert_false(
		WaterArea.WATER_BU_CHEAP.code.contains("hint_depth_texture"),
		"дешёвая версия без буфера глубины (4.7)")


func test_water_wave_spectrum_deterministic() -> void:
	# П14 4.3: спектр волн детерминирован (фиксированный seed) —
	# повторная сборка даёт те же волны; длинные первые (HIGH = 16 —
	# подмножество ULTRA = 32).
	for sea: bool in [true, false]:
		var first: Array = WaterArea.wave_spectrum(sea)
		var again: Array = WaterArea.wave_spectrum(sea)
		var a1: PackedVector4Array = first[0]
		var a2: PackedVector4Array = again[0]
		assert_eq(a1.size(), WaterArea.MAX_WAVES,
			"в спектре %d волн" % WaterArea.MAX_WAVES)
		for i: int in a1.size():
			assert_true((a1[i] as Vector4).is_equal_approx(a2[i]),
				"детерминизм волн (%s, %d)" % ["море" if sea else "озеро", i])
		# Длинные волны первые: k = 2π/λ не убывает (λ не растёт).
		for i: int in a1.size() - 1:
			assert_gt((a1[i] as Vector4).z, 0.0, "k > 0")
			assert_gte(
				(a1[i + 1] as Vector4).z, (a1[i] as Vector4).z - 0.0001,
				"длинные волны первые (%s, %d)" % ["море" if sea else "озеро", i])


func test_water_spectrum_sea_vs_lake() -> void:
	# П14 4.3: море — зыбь 12–60 м (60 %) и средние 2.5–10 м, суммарная
	# высота ~0.2 м RMS; озеро — почти гладь: длины 0.6–3 м, RMS ~1–3 см;
	# пена гребней — только у моря.
	var sea: Array = WaterArea.wave_spectrum(true)
	var lake: Array = WaterArea.wave_spectrum(false)
	var sea_a: PackedVector4Array = sea[0]
	var lake_a: PackedVector4Array = lake[0]
	var sea_b: PackedVector4Array = sea[1]
	var lake_b: PackedVector4Array = lake[1]
	var swell: int = 0
	var sum_sq_sea := 0.0
	var sum_sq_lake := 0.0
	for i: int in WaterArea.MAX_WAVES:
		var wave: Vector4 = sea_a[i]
		var length: float = TAU / wave.z
		sum_sq_sea += wave.w * wave.w
		sum_sq_lake += (lake_a[i] as Vector4).w * (lake_a[i] as Vector4).w
		if length > 10.0:
			swell += 1
			assert_between(length, WaterArea.SEA_SWELL_LEN.x,
				WaterArea.SEA_SWELL_LEN.y, "море: зыбь 12–60 м")
		else:
			assert_between(length, WaterArea.SEA_MEDIUM_LEN.x,
				WaterArea.SEA_MEDIUM_LEN.y, "море: средние 2.5–10 м")
		assert_between(TAU / (lake_a[i] as Vector4).z,
			WaterArea.LAKE_LEN.x, WaterArea.LAKE_LEN.y,
			"озеро: длины 0.6–3 м (почти гладь)")
		assert_almost_eq((lake_b[i] as Vector4).w, 0.0, 0.0001,
			"озеро: пены на гребнях нет")
	assert_between(swell, 15, 22, "море: зыби ~60 % спектра")
	assert_between(sqrt(sum_sq_sea), 0.12, 0.30,
		"море: суммарная высота волн ~0.2 м RMS (не шторм)")
	assert_between(sqrt(sum_sq_lake), 0.008, 0.035,
		"озеро: почти гладь, амплитуды 1–3 см")
	# Пена гребней у моря нормирована на совпадение фаз ≈ 0.55
	# (порог шейдера smoothstep(0.35, 0.55, crest)).
	var crest: float = 0.0
	for i: int in WaterArea.MAX_WAVES:
		var wa: Vector4 = sea_a[i]
		var wb: Vector4 = sea_b[i]
		crest += wb.w * wb.y * wa.z * wa.w
	assert_almost_eq(crest, 0.55, 0.02,
		"веса пены нормированы под порог шейдера")


func test_water_waves_and_ripple_by_tier() -> void:
	# П14 4.7: волны Герстнера 32 ULTRA / 16 HIGH / 8 SIMPLE и NORMAL;
	# рябь 3 / 2 / 1 слоя.
	assert_eq(WaterArea.wave_count_for_tier(GraphicsQuality.Tier.ULTRA), 32,
		"ULTRA — 32 волны")
	assert_eq(WaterArea.wave_count_for_tier(GraphicsQuality.Tier.HIGH), 16,
		"HIGH — 16 волн")
	assert_eq(WaterArea.wave_count_for_tier(GraphicsQuality.Tier.NORMAL), 8,
		"NORMAL — 8 волн")
	assert_eq(WaterArea.wave_count_for_tier(GraphicsQuality.Tier.SIMPLE), 8,
		"SIMPLE — 8 волн")
	assert_eq(WaterArea.ripple_layers_for_tier(GraphicsQuality.Tier.ULTRA), 3,
		"ULTRA — 3 слоя ряби")
	assert_eq(WaterArea.ripple_layers_for_tier(GraphicsQuality.Tier.HIGH), 2,
		"HIGH — 2 слоя ряби")
	assert_eq(WaterArea.ripple_layers_for_tier(GraphicsQuality.Tier.NORMAL), 1,
		"NORMAL — 1 слой ряби")
	assert_lte(WaterArea.wave_count_for_tier(GraphicsQuality.Tier.HIGH),
		WaterArea.MAX_WAVES, "HIGH — подмножество полного спектра")


func test_water_beer_and_fresnel_in_shader() -> void:
	# П14 4.1/4.2/4.4: поглощение Бера по каналам в коде шейдера
	# (exp по vec3), преломление смещает выборку экрана, френель —
	# Шлик (степень 5), пена процедурная (без текстур).
	var code := WaterArea.WATER_BU.code
	assert_true(code.contains("exp(-absorption * thickness)"),
		"поглощение Бера по каналам")
	assert_true(code.contains("vec3 transmit = exp("),
		"пропускание — вектор (красный гаснет первым)")
	assert_true(code.contains("refr_uv = SCREEN_UV + refr_off"),
		"преломление — смещение выборки экрана")
	assert_true(code.contains("-check_pos.z < surf_dist"),
		"выборка над водой не рвётся (проверка глубины)")
	assert_true(code.contains("pow(1.0 - max(dot(nrm, view_dir), 0.0), 5.0)"),
		"френель Шлика (степень 5)")
	assert_false(code.contains("texture_foam"),
		"пены-текстуры нет (процедурная)")
	assert_false(code.contains("texture_refraction"),
		"текстуры преломления Boujie нет")
	# П15 4 + 9.2: альфу ведут пена (непрозрачность ≤ 0.6) и мягкий
	# край (прозрачная кромка) — композит воды по-прежнему собран в
	# шейдере (поканальное поглощение в EMISSION).
	assert_true(code.contains("ALPHA = clamp(max(edge, foam * 0.6)"),
		"альфа — пена и мягкий край (П15)")


func test_water_night_follows_sky() -> void:
	# П14 4.6 (П15 3: отражение — движковое, небо в шейдер не пишется):
	# ночь — тёмная вода: update_sky гасит глубинные цвета вместе
	# с яркостью горизонта; отражение темнеет само (настоящее небо).
	WorldMaterials.textured_headless = true
	var area := WaterArea.new()
	add_child_autofree(area)
	var material := area._surface_material(false) as ShaderMaterial
	# День: светлый горизонт.
	area.update_sky(
		Color(0.3, 0.5, 0.8), Color(0.75, 0.75, 0.72),
		Vector3.UP, Color(1.0, 0.95, 0.85))
	var day_deep: Color = material.get_shader_parameter("color_deep")
	var day_shallow: Color = material.get_shader_parameter("color_shallow")
	# Ночь: тёмный горизонт — глубинные цвета гаснут (отражение неба
	# темнеет само — radiance ночного купола).
	area.update_sky(
		Color(0.02, 0.03, 0.06), Color(0.05, 0.06, 0.09),
		Vector3.DOWN, Color(0.4, 0.4, 0.5))
	var night_deep: Color = material.get_shader_parameter("color_deep")
	var night_shallow: Color = material.get_shader_parameter("color_shallow")
	assert_lt(night_deep.get_luminance(), day_deep.get_luminance() * 0.3,
		"ночью глубинный цвет гаснет")
	assert_lt(night_shallow.get_luminance(),
		day_shallow.get_luminance() * 0.3,
		"ночью мелководье гаснет")
	WorldMaterials.textured_headless = false


# --- П14 блок 2: освещение и нормали ---

func test_no_custom_light_model() -> void:
	# П14 2.1: кастомный light() с wrap-Ламбертом, toon-краем и своим GGX
	# удалён — стандартное PBR-освещение Godot (diffuse_lambert/specular
	# в render_mode — модели движка, не кастомный код).
	var text := GROUND_SHADER.code
	assert_false(text.contains("void light()"),
		"кастомного light() нет — PBR движка")
	assert_false(text.contains("float wrap"),
		"wrap-Ламберта нет (размывал освещение)")
	assert_false(text.contains("SHADOW_TINT"),
		"toon-тени соседних чанков не используются")
	assert_false(text.contains("flat_n"),
		"toon-край (плоская грань у границы Леса) убран")
	assert_false(text.contains("d_ggx"),
		"своего GGX-спекуляра нет — SPECULAR движка")
	# Блеск луж — через ROUGHNESS/SPECULAR (стандартный PBR).
	assert_true(text.contains("SPECULAR = mix("),
		"блеск луж — SPECULAR-выход")


func test_ao_goes_to_ao_output() -> void:
	# П14 2.3: AO из ORM (канал R) подаётся в AO-выход с умеренным
	# AO_LIGHT_AFFECT, а не умножением альбедо.
	var text := GROUND_SHADER.code
	assert_true(text.contains("AO = ao;"),
		"AO подаётся в AO-выход")
	assert_true(text.contains("AO_LIGHT_AFFECT"),
		"AO_LIGHT_AFFECT задаётся")
	assert_between(
		_extract_const(text, "AO_LIGHT_AFFECT_V"), 0.3, 0.7,
		"влияние AO на прямой свет умеренное")
	assert_false(text.contains("ALBEDO *= mix(mix(1.0, ao"),
		"альбедо больше не затемняется AO вручную")


func test_normal_strength_near_far() -> void:
	# П14 2.2: whiteout-смешивание нормалей слоёв с нормалью рельефа,
	# сила вблизи 1.3–1.6, к дали гаснет.
	var text := GROUND_SHADER.code
	assert_between(
		_extract_uniform(text, "normal_near"), 1.3, 1.6,
		"сила нормалей вблизи 1.3–1.6")
	var far_strength: float = _extract_uniform(text, "normal_far")
	assert_between(far_strength, 0.5, 1.0, "к дали сила гаснет")
	assert_true(text.contains("tangent_perturb"),
		"whiteout: касательная часть нормал-карты над нормалью рельефа")


static func _extract_const(text: String, name: String) -> float:
	var regex := RegEx.new()
	regex.compile("const float %s = ([\\d.]+);" % name)
	var found := regex.search(text)
	if found == null:
		push_error("константа %s не найдена" % name)
		return -1.0
	return float(found.get_string(1))


static func _extract_uniform(text: String, name: String) -> float:
	var regex := RegEx.new()
	regex.compile("uniform float %s = (-?[\\d.]+);" % name)
	var found := regex.search(text)
	if found == null:
		push_error("uniform %s не найден" % name)
		return -1.0
	return float(found.get_string(1))
