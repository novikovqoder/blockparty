# Тесты света и атмосферы (шаг 4 П4.5, раздел 16 SPEC): тёплая тональная
# коррекция и цветокоррекция, дымка по высоте, тёплое солнце у горизонта
# и уровни качества картинки (блок е vfx-fix: постобработка — glow, SSAO
# и виньетка — и тяжёлый объёмный туман только в «Высоком качестве»).
# П5.9 блок 6: небо мира — Sky3D; риг сцены проверяется на месте, DayCycle
# гоняется на живом Sky3D (светила, купол, палитры времён суток).
extends GutTest

const WORLD: PackedScene = preload("res://scenes/world_scene.tscn")
const B: Balance = preload("res://gameplay/balance.tres")
const VPAL: VisualPalette = preload("res://assets/visual_palette.tres")


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
	var sun: DirectionalLight3D = scene.get_node("WorldEnvironment/SunLight")
	assert_true(sun.shadow_enabled, "тени солнца включены")
	assert_gt(sun.shadow_blur, 1.0, "тени мягкие (shadow_blur)")
	scene.free()


func test_quality_tiers() -> void:
	# SIMPLE — без теней и пост-эффектов (слабые GPU); NORMAL — тени и
	# базовая картинка; HIGH — постобработка (блок е: аккуратный glow
	# SOFTLIGHT, SSAO) и объёмный туман (тяжёлый эффект). Луна (П5.9
	# блок 6: Sky3D) — те же правила теней, что у солнца.
	for tier: int in [
		GraphicsQuality.Tier.SIMPLE,
		GraphicsQuality.Tier.NORMAL,
		GraphicsQuality.Tier.HIGH,
	]:
		var env := Environment.new()
		var sun := DirectionalLight3D.new()
		var moon := DirectionalLight3D.new()
		moon.shadow_enabled = true
		GraphicsQuality.apply(env, sun, tier, null, moon)
		var high: bool = tier == GraphicsQuality.Tier.HIGH
		assert_eq(
			sun.shadow_enabled, tier != GraphicsQuality.Tier.SIMPLE,
			"уровень %d: тени" % tier,
		)
		assert_eq(
			moon.shadow_enabled, tier != GraphicsQuality.Tier.SIMPLE,
			"уровень %d: тени луны как у солнца" % tier,
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
		# П5.7 блок 7: «Простая графика» сэмплит текстуры из мипа 1K.
		var viewport := SubViewport.new()
		GraphicsQuality.apply(env, sun, tier, viewport, moon)
		assert_eq(
			viewport.texture_mipmap_bias,
			GraphicsQuality.SIMPLE_MIPMAP_BIAS if tier == GraphicsQuality.Tier.SIMPLE else 0.0,
			"уровень %d: смещение мипов текстур" % tier,
		)
		viewport.free()
		sun.free()
		moon.free()


func test_simple_tier_character_lod_closer() -> void:
	# П5.7 блок 7 (SPEC п. 7): «Простая графика» приближает переключение
	# LOD персонажей (облегченные копии с ~8 м), обычные уровни оставляют
	# базовую дистанцию модели.
	var simple := Settings.simple_graphics
	Settings.simple_graphics = false
	assert_eq(
		GraphicsQuality.character_lod_distance(18.0), 18.0,
		"обычный уровень: базовая дистанция LOD",
	)
	Settings.simple_graphics = true
	assert_almost_eq(
		GraphicsQuality.character_lod_distance(18.0),
		18.0 * GraphicsQuality.CHARACTER_LOD_FACTOR, 0.01,
		"«Простая графика»: LOD ближе",
	)
	Settings.simple_graphics = simple


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


## Риг неба Sky3D в дереве теста (П5.9 блок 6): Sky3D сам создаёт светила,
## купол и TimeOfDay; DayCycle ведёт его по часам мира Session.world_time.
func _make_sky_rig() -> Sky3D:
	var sky := Sky3D.new()
	add_child(sky)
	return sky


func test_sun_warmer_at_sunset_than_noon() -> void:
	# Раздел 16: «цвет солнца тёплый утром и вечером» — DayCycle красит
	# светило смешением палитр времён суток (VisualPalette), купол Sky3D
	# переносит цвет на DirectionalLight: закат краснее полудня.
	var sky := _make_sky_rig()
	var cycle := DayCycle.new()
	cycle.setup(sky.sun, sky)
	var saved := Session.world_time
	Session.world_time = 0.3 * B.day_cycle_sec  # полдень (день 60 % суток)
	cycle._process(0.0)
	var noon: Color = sky.sun.light_color
	Session.world_time = 0.58 * B.day_cycle_sec  # золотой час заката
	cycle._process(0.0)
	var sunset: Color = sky.sun.light_color
	Session.world_time = saved
	assert_gt(
		(sunset.r - sunset.b) - (noon.r - noon.b), 0.05,
		"закатное солнце заметно теплее полудня",
	)
	cycle.free()
	sky.free()


func test_height_fog_from_balance() -> void:
	# Дымка по высоте применяется из Balance каждый кадр DayCycle —
	# значения согласованы (плотность положительная, база у земли);
	# ambient красится палитрой дня (П5.9 блок 6, точное смешение).
	assert_gt(B.fog_height_density, 0.0, "плотность высотного тумана > 0")
	assert_between(B.fog_height_m, 0.0, 3.0, "база дымки у земли")
	var sky := _make_sky_rig()
	var cycle := DayCycle.new()
	cycle.setup(sky.sun, sky)
	var saved := Session.world_time
	Session.world_time = 0.3 * B.day_cycle_sec
	cycle._process(0.0)
	Session.world_time = saved
	var env := sky.environment
	assert_almost_eq(env.fog_height, B.fog_height_m, 0.001, "высота дымки — из Balance")
	assert_almost_eq(
		env.fog_height_density, B.fog_height_density, 0.001,
		"плотность дымки — из Balance",
	)
	assert_almost_eq(
		env.ambient_light_color.r, VPAL.day_ambient.r, 0.001,
		"ambient полудня — палитра дня (r)",
	)
	assert_almost_eq(
		env.ambient_light_color.g, VPAL.day_ambient.g, 0.001,
		"ambient полудня — палитра дня (g)",
	)
	assert_almost_eq(
		env.ambient_light_color.b, VPAL.day_ambient.b, 0.001,
		"ambient полудня — палитра дня (b)",
	)
	cycle.free()
	sky.free()


func test_zone_fog_volume() -> void:
	# Сгусток тумана зоны («Высокое качество»): широкий, плотный, цвет зоны.
	var volume := GraphicsQuality.make_zone_fog(Vector3.ZERO, Color.WHITE)
	var material := volume.material as FogMaterial
	assert_gt(material.density, 0.0, "плотность тумана зоны положительная")
	assert_gt(volume.size.x, 30.0, "сгусток шире 30 м")
	assert_gt(volume.size.y, 2.0, "сгусток выше 2 м")
	assert_eq(material.albedo, Color.WHITE, "цвет зоны передан в материал")
	volume.free()


func test_world_scene_sky3d_rig() -> void:
	# П5.9 блок 6: небо мира — Sky3D (MIT, addons/sky_3d). Сцена мира
	# держит полный риг аддона; собственный ход времени TimeOfDay выключен
	# (часы ведёт сеть через Session.world_time), экранный туман купола
	# не нужен — туман ведёт Environment. Текстуры звёзд — процедурные
	# текстуры проекта (лицензии CC0, см. assets/third_party/LICENSES.md).
	var scene := WORLD.instantiate()
	var world_env: WorldEnvironment = scene.get_node("WorldEnvironment")
	assert_true(world_env is Sky3D, "окружение мира — узел Sky3D")
	var material := world_env.environment.sky.sky_material as ShaderMaterial
	assert_not_null(material, "материал неба — шейдерный")
	assert_eq(
		material.shader.resource_path,
		"res://addons/sky_3d/shaders/SkyMaterial.gdshader",
		"шейдер неба — Sky3D",
	)
	var dome_node: SkyDome = scene.get_node("WorldEnvironment/SkyDome")
	assert_eq(
		dome_node.starmap_texture.resource_path,
		"res://assets/visual/sky_starmap.png",
		"карта звёзд — процедурная текстура проекта",
	)
	assert_eq(
		dome_node.star_field_texture.resource_path,
		"res://assets/visual/sky_starfield.png",
		"россыпь звёзд — процедурная текстура проекта",
	)
	var tod: TimeOfDay = scene.get_node("WorldEnvironment/TimeOfDay")
	assert_false(tod.game_time_enabled, "игровое время TimeOfDay выключено")
	assert_false(tod.editor_time_enabled, "редакторное время TimeOfDay выключено")
	var dome: SkyDome = scene.get_node("WorldEnvironment/SkyDome")
	assert_false(dome.fog_visible, "экранный туман Sky3D не используется")
	assert_eq(
		dome.moon_light_energy, B.moon_energy_night,
		"энергия луны — из Balance",
	)
	var moon: DirectionalLight3D = scene.get_node("WorldEnvironment/MoonLight")
	assert_almost_eq(
		moon.light_energy, B.moon_energy_night, 0.001,
		"свет луны в сцене — из Balance",
	)
	scene.free()


func test_tonemap_exposure_brighter_at_night() -> void:
	# П5.7 блок 3: «мягкая светлая ночь» (раздел 7 SPEC) под тёмным небом
	# Sky3D — экспозиция тонемапа ночью выше дневной, день — единица.
	var sky := _make_sky_rig()
	var cycle := DayCycle.new()
	cycle.setup(sky.sun, sky)
	var saved := Session.world_time
	Session.world_time = 0.3 * B.day_cycle_sec
	cycle._process(0.0)
	var day_exposure: float = sky.environment.tonemap_exposure
	Session.world_time = 0.8 * B.day_cycle_sec
	cycle._process(0.0)
	var night_exposure: float = sky.environment.tonemap_exposure
	Session.world_time = saved
	assert_almost_eq(day_exposure, 1.0, 0.001, "днём экспозиция — единица")
	assert_gt(night_exposure, day_exposure + 0.5,
		"ночью экспозиция заметно выше (светлая ночь)")
	cycle.free()
	sky.free()


func test_day_cycle_leads_dome_positions() -> void:
	# П5.9 блок 6: купол Sky3D ведут часы мира — DayCycle ставит солнце
	# в положение DayMath.sun_direction (полярный угол от зенита) и крутит
	# звёздное небо полным оборотом за сутки; луна ходит напротив солнца.
	var sky := _make_sky_rig()
	var cycle := DayCycle.new()
	cycle.setup(sky.sun, sky)
	var saved := Session.world_time
	Session.world_time = 0.3 * B.day_cycle_sec  # полдень
	cycle._process(0.0)
	Session.world_time = saved
	var dome: SkyDome = sky.sky
	var to_sun := DayMath.sun_direction(0.3 * B.day_cycle_sec)
	assert_almost_eq(
		dome.sun_altitude, acos(clampf(to_sun.y, -1.0, 1.0)), 0.001,
		"купол смотрит на солнце DayMath (высота)",
	)
	assert_almost_eq(
		dome.sun_azimuth, atan2(to_sun.x, to_sun.z), 0.001,
		"купол смотрит на солнце DayMath (азимут)",
	)
	assert_almost_eq(
		dome.moon_altitude, PI - dome.sun_altitude, 0.001,
		"луна напротив солнца (высота)",
	)
	var star_spin: float = dome.sky_material.get_shader_parameter("star_rotation")
	assert_almost_eq(
		star_spin, TAU * DayMath.day_fraction(0.3 * B.day_cycle_sec), 0.001,
		"звёзды крутятся полным оборотом за сутки мира",
	)
	cycle.free()
	sky.free()
