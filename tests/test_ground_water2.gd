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
