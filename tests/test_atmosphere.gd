# Тесты света и атмосферы (шаг 4 П4.5, раздел 16 SPEC): тёплая тональная
# коррекция и цветокоррекция, дымка по высоте, тёплое солнце у горизонта
# и уровни качества картинки (блок е vfx-fix: постобработка — glow, SSAO
# и виньетка — и тяжёлый объёмный туман только в «Высоком качестве»).
extends GutTest

const WORLD: PackedScene = preload("res://scenes/world_scene.tscn")
const B: Balance = preload("res://gameplay/balance.tres")


func test_world_scene_atmosphere_base() -> void:
	# Сцена мира (узлы без запуска _ready): база без постобработки (glow
	# и SSAO включает «Высокое качество»), точка белого тёплая,
	# цветокоррекция контраста и насыщенности, дымка по высоте,
	# тени солнца включены и мягкие.
	var scene := WORLD.instantiate()
	var env: Environment = scene.get_node("WorldEnvironment").environment
	assert_false(env.glow_enabled, "в базе glow выключен (только «Высокое»)")
	assert_false(env.ssao_enabled, "в базе SSAO выключен (только «Высокое»)")
	assert_gt(env.tonemap_white, 1.0, "точка белого приподнята (светлее)")
	assert_true(env.adjustment_enabled, "цветокоррекция включена")
	assert_gt(env.adjustment_saturation, 1.0, "насыщенность чуть выше единицы")
	assert_gt(env.fog_height_density, 0.0, "дымка по высоте включена")
	var sun: DirectionalLight3D = scene.get_node("Sun")
	assert_true(sun.shadow_enabled, "тени солнца включены")
	assert_gt(sun.shadow_blur, 1.0, "тени мягкие (shadow_blur)")
	scene.free()


func test_quality_tiers() -> void:
	# SIMPLE — без теней и пост-эффектов (слабые GPU); NORMAL — тени и
	# базовая картинка; HIGH — постобработка (блок е: аккуратный glow
	# SOFTLIGHT, SSAO) и объёмный туман (тяжёлый эффект).
	for tier: int in [
		GraphicsQuality.Tier.SIMPLE,
		GraphicsQuality.Tier.NORMAL,
		GraphicsQuality.Tier.HIGH,
	]:
		var env := Environment.new()
		var sun := DirectionalLight3D.new()
		GraphicsQuality.apply(env, sun, tier)
		var high: bool = tier == GraphicsQuality.Tier.HIGH
		assert_eq(
			sun.shadow_enabled, tier != GraphicsQuality.Tier.SIMPLE,
			"уровень %d: тени" % tier,
		)
		assert_eq(env.ssao_enabled, high, "уровень %d: SSAO только в «Высоком»" % tier)
		assert_eq(env.glow_enabled, high, "уровень %d: glow только в «Высоком»" % tier)
		if high:
			assert_eq(
				env.glow_blend_mode, Environment.GLOW_BLEND_MODE_SOFTLIGHT,
				"glow мягкий (SOFTLIGHT, не выбеливает)",
			)
			assert_gt(env.glow_bloom, 0.0, "порог bloom отсекает не-источники")
		assert_eq(
			env.volumetric_fog_enabled, high,
			"уровень %d: объёмный туман только в «Высоком»" % tier,
		)
		sun.free()


func test_vignette_layer() -> void:
	# Виньетка (блок е): полноэкранная (якоря и офсеты на весь экран),
	# клики проходят насквозь, материал — шейдер vignette.gdshader.
	var rect := GraphicsQuality.make_vignette()
	assert_almost_eq(rect.anchor_left, 0.0, 0.001, "виньетка: левый край у 0")
	assert_almost_eq(rect.anchor_right, 1.0, 0.001, "виньетка: правый край у 1")
	assert_almost_eq(rect.anchor_top, 0.0, 0.001, "виньетка: верх у 0")
	assert_almost_eq(rect.anchor_bottom, 1.0, 0.001, "виньетка: низ у 1")
	assert_eq(
		rect.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"виньетка не ловит мышь",
	)
	var material := rect.material as ShaderMaterial
	assert_not_null(material, "материал виньетки — ShaderMaterial")
	assert_eq(
		material.shader.resource_path, "res://assets/shaders/vignette.gdshader",
		"шейдер виньетки подключён",
	)
	rect.free()


func test_tier_from_settings() -> void:
	# Настройки: по умолчанию NORMAL, флаги поднимают до SIMPLE или HIGH
	# (HIGH сильнее — «простая графика» важнее для слабых GPU).
	var simple := Settings.simple_graphics
	var high := Settings.high_quality
	Settings.simple_graphics = false
	Settings.high_quality = false
	assert_eq(
		GraphicsQuality.tier_from_settings(), GraphicsQuality.Tier.NORMAL,
		"по умолчанию обычное качество",
	)
	Settings.simple_graphics = true
	assert_eq(
		GraphicsQuality.tier_from_settings(), GraphicsQuality.Tier.SIMPLE,
		"«Простая графика»",
	)
	Settings.simple_graphics = false
	Settings.high_quality = true
	assert_eq(
		GraphicsQuality.tier_from_settings(), GraphicsQuality.Tier.HIGH,
		"«Высокое качество»",
	)
	Settings.simple_graphics = simple
	Settings.high_quality = high


func test_sun_warmer_at_sunset_than_noon() -> void:
	# Раздел 16: «цвет солнца тёплый утром и вечером» — DayCycle ведёт
	# light_color по DayMath.warmth, закатное солнце краснее полудня.
	var sun := DirectionalLight3D.new()
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	world_env.environment = env
	var cycle := DayCycle.new()
	cycle.setup(sun, world_env)
	var saved := Session.world_time
	Session.world_time = 0.3 * B.day_cycle_sec  # полдень (день 60 % суток)
	cycle._process(0.0)
	var noon: Color = sun.light_color
	Session.world_time = 0.58 * B.day_cycle_sec  # золотой час заката
	cycle._process(0.0)
	var sunset: Color = sun.light_color
	Session.world_time = saved
	assert_gt(
		(sunset.r - sunset.b) - (noon.r - noon.b), 0.05,
		"закатное солнце заметно теплее полудня",
	)
	cycle.free()
	sun.free()
	world_env.free()


func test_height_fog_from_balance() -> void:
	# Дымка по высоте применяется из Balance каждый кадр DayCycle —
	# значения согласованы (плотность положительная, база у земли).
	assert_gt(B.fog_height_density, 0.0, "плотность высотного тумана > 0")
	assert_between(B.fog_height_m, 0.0, 3.0, "база дымки у земли")
	var sun := DirectionalLight3D.new()
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	world_env.environment = env
	var cycle := DayCycle.new()
	cycle.setup(sun, world_env)
	var saved := Session.world_time
	Session.world_time = 0.3 * B.day_cycle_sec
	cycle._process(0.0)
	Session.world_time = saved
	assert_almost_eq(env.fog_height, B.fog_height_m, 0.001, "высота дымки — из Balance")
	assert_almost_eq(
		env.fog_height_density, B.fog_height_density, 0.001,
		"плотность дымки — из Balance",
	)
	assert_gt(
		env.ambient_light_color.r, env.ambient_light_color.b,
		"дневной ambient тёплый (r > b)",
	)
	cycle.free()
	sun.free()
	world_env.free()


func test_zone_fog_volume() -> void:
	# Сгусток тумана зоны («Высокое качество»): широкий, плотный, цвет зоны.
	var volume := GraphicsQuality.make_zone_fog(Vector3.ZERO, Color.WHITE)
	var material := volume.material as FogMaterial
	assert_gt(material.density, 0.0, "плотность тумана зоны положительная")
	assert_gt(volume.size.x, 30.0, "сгусток шире 30 м")
	assert_gt(volume.size.y, 2.0, "сгусток выше 2 м")
	assert_eq(material.albedo, Color.WHITE, "цвет зоны передан в материал")
	volume.free()
