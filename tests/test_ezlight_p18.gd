# Тесты П18 Сборки 1 п.5 «Пресет света ezTree»: день — сильное солнце,
# ровный белый ambient, экспозиция и голубой экспоненциальный туман демо
# (0x94b9f8); ночь и закат пресетом не трогаются (ночь тёмная), снятая
# галочка F3 возвращает «текущий» баланс. Переходы: по времени суток —
# dayness, по галочке — плавный _eztree_mix.
extends GutTest

const B: Balance = preload("res://gameplay/balance.tres")
const VPAL: VisualPalette = preload("res://assets/visual_palette.tres")


## Базовая кривая ambient суток по источнику окружения (без пресета).
func _base_ambient(env: Environment, world_time: float) -> float:
	if env.ambient_light_source == Environment.AMBIENT_SOURCE_SKY:
		return DayMath.ambient_energy_sky(world_time)
	return DayMath.ambient_energy(world_time)


## Риг неба Sky3D (как test_atmosphere): купол сам создаёт светила и
## окружение, DayCycle ведёт их по часам Session.world_time.
func _make_sky_rig() -> Sky3D:
	var sky := Sky3D.new()
	add_child_autofree(sky)
	return sky


func test_day_preset_sets_demo_light_and_fog() -> void:
	# Полдень пресета: солнце сильное (демо DirectionalLight 5), ambient
	# ровный белый 0.4-эквивалент (при источнике-небе — ×AMBIENT_SKY_SCALE),
	# экспозиция демо, туман — цвет и плотность демо.
	var sky := _make_sky_rig()
	var cycle := DayCycle.new()
	cycle.setup(sky.sun, sky)
	assert_true(cycle.is_in_group(DayCycle.GROUP),
		"цикл в группе — галочка F3 находит его без прямых ссылок")
	cycle.eztree_light = true
	cycle._eztree_mix = 1.0
	var saved := Session.world_time
	Session.world_time = 0.3 * B.day_cycle_sec  # полдень (день 60 % суток)
	cycle._process(0.0)
	var env: Environment = sky.environment
	assert_almost_eq(sky.sky.sun_light_energy, B.eztree_sun_energy, 0.0001,
		"полдень: солнце пресета (сильное, как в демо)")
	assert_gt(B.eztree_sun_energy, B.sun_energy_noon * 3.0,
		"пресет заметно сильнее базового баланса (контраст демо)")
	assert_almost_eq(env.tonemap_exposure, B.eztree_exposure, 0.0001,
		"экспозиция пресета (демо 2, AgX темнее — подобрано)")
	assert_almost_eq(env.fog_density, B.eztree_fog_density, 0.0000001,
		"плотность тумана демо (0.0015/k на метр)")
	assert_almost_eq(env.fog_light_color.r, B.eztree_fog_color.r, 0.0001,
		"цвет тумана демо: R")
	assert_almost_eq(env.fog_light_color.g, B.eztree_fog_color.g, 0.0001,
		"цвет тумана демо: G")
	assert_almost_eq(env.fog_light_color.b, B.eztree_fog_color.b, 0.0001,
		"цвет тумана демо: B")
	assert_almost_eq(env.ambient_light_color.r, 1.0, 0.0001,
		"ambient ровный белый: R")
	assert_almost_eq(env.ambient_light_color.b, 1.0, 0.0001,
		"ambient ровный белый: B")
	# Риг Sky3D по умолчанию — источник-небо (как мир, П17 п.10):
	# «плоский» эквивалент 0.4 демо ниже на AMBIENT_SKY_SCALE.
	assert_almost_eq(env.ambient_light_energy,
		B.eztree_ambient_energy * DayMath.AMBIENT_SKY_SCALE, 0.0001,
		"ambient-энергия — «плоский» эквивалент 0.4 демо (×небо)")
	# При плоском COLOR-источнике (лаборатории света) — ровные 0.4.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	cycle._process(0.0)
	assert_almost_eq(env.ambient_light_energy, B.eztree_ambient_energy,
		0.0001, "при COLOR-источнике ambient пресета — ровные 0.4")
	Session.world_time = saved
	cycle.free()


func test_current_preset_returns_base_values() -> void:
	# Снятая галочка (после хода fade) возвращает «текущий» баланс:
	# плотность и цвет тумана из Balance/палитры, экспозиция 1, солнце
	# базовое. Плавность: за один такт длиннее EZTREE_FADE_SEC микс доезжает.
	var sky := _make_sky_rig()
	var cycle := DayCycle.new()
	cycle.setup(sky.sun, sky)
	var saved := Session.world_time
	Session.world_time = 0.3 * B.day_cycle_sec  # полдень
	cycle.eztree_light = false
	cycle._process(DayCycle.EZTREE_FADE_SEC)
	var env: Environment = sky.environment
	assert_almost_eq(sky.sky.sun_light_energy, B.sun_energy_noon, 0.0001,
		"«текущий»: солнце базового баланса")
	assert_almost_eq(env.tonemap_exposure, 1.0, 0.0001,
		"«текущий»: дневная экспозиция 1")
	assert_almost_eq(env.fog_density, B.fog_density, 0.0000001,
		"«текущий»: плотность тумана из Balance")
	# Цвет тумана — чистая палитра суток (пресет больше не подмешан).
	var mixes := DayMath.palette_mixes(Session.world_time)
	assert_almost_eq(env.fog_light_color.r, cycle._mix4(VPAL.dawn_fog,
		VPAL.day_fog, VPAL.dusk_fog, VPAL.night_fog, mixes).r, 0.0001,
		"«текущий»: туман палитры суток, без подмесы пресета")
	assert_almost_eq(env.ambient_light_energy, _base_ambient(env,
		Session.world_time), 0.0001, "«текущий»: кривая ambient суток")
	Session.world_time = saved
	cycle.free()


func test_night_untouched_by_preset() -> void:
	# Ночь пресетом не трогается: экспозиция ночи, туман палитры ночи
	# с базовой плотностью, ambient ночи, солнце — базовая энергия
	# (долю пресета обнуляет dayness = 0) — ночь остаётся тёмной.
	var sky := _make_sky_rig()
	var cycle := DayCycle.new()
	cycle.setup(sky.sun, sky)
	cycle.eztree_light = true
	cycle._eztree_mix = 1.0
	var saved := Session.world_time
	Session.world_time = 0.8 * B.day_cycle_sec  # полночь (ночь 60–100 %)
	cycle._process(0.0)
	var env: Environment = sky.environment
	assert_almost_eq(env.tonemap_exposure, DayCycle.NIGHT_EXPOSURE, 0.0001,
		"ночь: повышенная экспозиция «мягкой светлой ночи»")
	assert_almost_eq(env.fog_density, B.fog_density, 0.0000001,
		"ночь: плотность тумана базовая, не пресета")
	assert_almost_eq(env.ambient_light_energy, _base_ambient(env,
		Session.world_time), 0.0001,
		"ночь: кривая ambient суток (не 0.4 демо)")
	assert_gt(env.ambient_light_color.r + env.ambient_light_color.g
		+ env.ambient_light_color.b, 0.3,
		"ночь: ambient палитры ночи, не белый пресета")
	assert_lt(env.ambient_light_color.g, 0.9,
		"ночь: ambient не ровный белый")
	assert_almost_eq(sky.sky.sun_light_energy, B.sun_energy_noon, 0.0001,
		"ночь: солнце базовой энергии (пресет спит)")
	Session.world_time = saved
	cycle.free()


func test_f3_ezlight_and_lodblend_checkboxes() -> void:
	# П18 Сборки 1 п.5: галочки «Свет: ezTree» и «LOD-перетекание» в
	# EFFECTS с подписями i18n; пресет света и перетекание — не уровневые
	# эффекты, действуют на всех уровнях графики.
	var panel := DebugPanel.new()
	add_child_autofree(panel)
	assert_true(panel.EFFECTS.has(&"ezlight"), "галочка «Свет: ezTree» есть")
	assert_true(panel.EFFECTS.has(&"lodblend"), "галочка «LOD-перетекание» есть")
	assert_true(panel.EFFECT_LABELS.has(&"ezlight"),
		"у «Свет: ezTree» есть подпись i18n")
	assert_true(panel.EFFECT_LABELS.has(&"lodblend"),
		"у «LOD-перетекание» есть подпись i18n")
	panel.watch_graphics(Environment.new(), null, GraphicsQuality.Tier.SIMPLE)
	assert_true(panel._tier_effect_on(&"ezlight"), "SIMPLE: пресет света есть")
	assert_true(panel._tier_effect_on(&"lodblend"), "SIMPLE: перетекание есть")
	panel.watch_graphics(Environment.new(), null, GraphicsQuality.Tier.ULTRA)
	assert_true(panel._tier_effect_on(&"ezlight"), "ULTRA: как везде")
	assert_true(panel._tier_effect_on(&"lodblend"), "ULTRA: как везде")
