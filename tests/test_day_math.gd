# Тесты математики цикла дня (раздел 7, этап П2): сутки 20 минут, день 60%,
# мягкая светлая ночь. Чистые функции DayMath — проверяются периодичность,
# границы дня/ночи, положение солнца и энергия (числа — в Balance).
# П5.9 блок 6: небо красит Sky3D смешением палитр времён суток — веса
# palette_mixes проверяются на сумму, фазы и непрерывность шва полуночи.
extends GutTest

const B: Balance = preload("res://gameplay/balance.tres")
const VPAL: VisualPalette = preload("res://assets/visual_palette.tres")

## Допуск сравнения цветов/плавающих (тонкая математика, не физика).
const EPS: float = 0.001


func test_day_fraction_wraps() -> void:
	assert_almost_eq(DayMath.day_fraction(0.0), 0.0, EPS, "нуль — рассвет")
	assert_almost_eq(DayMath.day_fraction(B.day_cycle_sec), 0.0, EPS, "сутки заворачиваются")
	assert_almost_eq(
		DayMath.day_fraction(B.day_cycle_sec * 7.0 + 3.0),
		DayMath.day_fraction(3.0), EPS,
		"периодичность от целых суток",
	)


func test_day_and_night_boundaries() -> void:
	# day_share = 0.6: до 0.6 суток — день, после — ночь.
	assert_true(DayMath.is_day(0.0), "рассвет — уже день")
	assert_true(DayMath.is_day(B.day_cycle_sec * (B.day_share - EPS)), "конец дня")
	assert_false(DayMath.is_day(B.day_cycle_sec * (B.day_share + EPS)), "начало ночи")
	assert_false(DayMath.is_day(B.day_cycle_sec * 0.95), "глубокая ночь")


func test_sun_above_horizon_only_in_day() -> void:
	# Днём солнце не ниже горизонта (на самом рассвете — ровно на нём),
	# ночью — под ним (свет выключен).
	var step: float = B.day_cycle_sec / 48.0
	for i: int in range(48):
		var t: float = step * i
		var direction := DayMath.sun_direction(t)
		if DayMath.is_day(t):
			assert_gte(direction.y, 0.0, "днём солнце не ниже горизонта (t=%.1f)" % t)
		else:
			assert_lt(direction.y, 0.0, "ночью солнце под горизонтом (t=%.1f)" % t)


func test_sun_energy_curve() -> void:
	assert_almost_eq(DayMath.sun_energy(B.day_cycle_sec * 0.7), 0.0, EPS, "ночью ноль")
	# Полдень — середина дня; энергия = sun_energy_noon (0.35 + 0.65 × 1).
	assert_almost_eq(
		DayMath.sun_energy(B.day_cycle_sec * B.day_share * 0.5), B.sun_energy_noon, 0.001,
		"в полдень — максимум из Balance",
	)
	# Рассвет: sin(0) = 0 → 0.35 от полуденной.
	assert_almost_eq(
		DayMath.sun_energy(0.0), B.sun_energy_noon * 0.35, 0.001, "на рассвете — треть",
	)


func test_max_sun_elevation() -> void:
	# Высшая точка солнца — sun_max_elevation из Balance.
	var noon := DayMath.sun_direction(B.day_cycle_sec * B.day_share * 0.5)
	assert_almost_eq(asin(noon.y), B.sun_max_elevation, 0.01, "максимум подъёма")


func test_night_is_soft_and_bright() -> void:
	# «Ночь мягкая, светлая» (раздел 7): ambient не гаснет ниже 0.16,
	# небо не чернеет полностью (П5.9 блок 6: ночное небо — палитра ночи
	# из VisualPalette, полночь — её чистый вес).
	for t: float in [B.day_cycle_sec * 0.7, B.day_cycle_sec * 0.9]:
		assert_gt(DayMath.ambient_energy(t), 0.15, "ambient ночи не ниже 0.16")
	assert_almost_eq(DayMath.ambient_energy(B.day_cycle_sec * 0.7), 0.16, EPS)
	var midnight := DayMath.palette_mixes(B.day_cycle_sec * 0.8)
	assert_almost_eq(midnight.w, 1.0, EPS, "полночь — чистая палитра ночи")
	assert_gt(VPAL.night_sky_top.v, 0.05, "ночное небо не чёрное")


func test_dayness_and_warmth() -> void:
	assert_almost_eq(DayMath.dayness(0.0), 0.0, EPS, "рассвет — день ещё не полный")
	assert_almost_eq(DayMath.warmth(0.0), 1.0, EPS, "у горизонта — тёплый тон")
	# Полдень: день полный, теплоты нет.
	assert_almost_eq(DayMath.dayness(B.day_cycle_sec * 0.3), 1.0, 0.01)
	assert_almost_eq(DayMath.warmth(B.day_cycle_sec * 0.3), 0.0, 0.01)
	assert_almost_eq(DayMath.dayness(B.day_cycle_sec * 0.7), 0.0, EPS, "ночью dayness 0")


func test_palette_times_of_day() -> void:
	# П5.9 блок 6 (раздел 16 «Визуальная цель»): палитры времён суток —
	# рассвет и закат с тёплыми горизонтами (r > b), день с холодным верхом
	# (b > r), ночь сине-фиолетовая и не чёрная.
	assert_gt(
		VPAL.dawn_sky_horizon.r - VPAL.dawn_sky_horizon.b, 0.0,
		"рассветный горизонт тёплый (r > b)",
	)
	assert_gt(
		VPAL.dusk_sky_horizon.r - VPAL.dusk_sky_horizon.b, 0.0,
		"закатный горизонт тёплый (r > b)",
	)
	assert_gt(
		VPAL.day_sky_top.b - VPAL.day_sky_top.r, 0.0,
		"полдень холодный (b > r)",
	)
	assert_gt(
		VPAL.night_sky_top.b - VPAL.night_sky_top.r, 0.0,
		"ночь сине-фиолетовая (b > r)",
	)
	assert_between(
		VPAL.night_sky_top.v, 0.02, 0.25, "ночь тёмная, но не чёрная"
	)


func test_palette_mixes_sum_to_one_all_day() -> void:
	# П5.9 блок 6: веса палитр (рассвет, день, закат, ночь) в сумме дают
	# единицу в любой точке суток — небо не чернеет и не пересвечивается.
	var step: float = B.day_cycle_sec / 60.0
	for i: int in range(60):
		var t: float = step * i
		var mixes := DayMath.palette_mixes(t)
		assert_almost_eq(
			mixes.x + mixes.y + mixes.z + mixes.w, 1.0, EPS,
			"сумма весов палитр = 1 (t=%.1f)" % t,
		)
		assert_between(mixes.x, 0.0, 1.0, "вес рассвета корректен (t=%.1f)" % t)
		assert_between(mixes.y, 0.0, 1.0, "вес дня корректен (t=%.1f)" % t)
		assert_between(mixes.z, 0.0, 1.0, "вес заката корректен (t=%.1f)" % t)
		assert_between(mixes.w, 0.0, 1.0, "вес ночи корректен (t=%.1f)" % t)


func test_palette_mixes_phases() -> void:
	# Полдень — чистый день, полночь — чистая ночь; закат (0.58 суток,
	# солнце низко) замешан из тёплой палитры — переход плавный,
	# без скачка на границе дня.
	var noon := DayMath.palette_mixes(B.day_cycle_sec * 0.3)
	assert_almost_eq(noon.y, 1.0, 0.01, "полдень — палитра дня")
	assert_almost_eq(noon.w, 0.0, EPS, "ночную палитру не видно")
	var midnight := DayMath.palette_mixes(B.day_cycle_sec * 0.8)
	assert_almost_eq(midnight.w, 1.0, EPS, "полночь — палитра ночи")
	var sunset := DayMath.palette_mixes(B.day_cycle_sec * 0.58)
	assert_gt(sunset.z, sunset.y + 0.1, "закатная палитра сильнее дневной")
	assert_between(sunset.w, 0.0, 0.9, "закат ещё не ночь (ночь < 0.9)")
	# Смешивание непрерывно на границе дня и ночи: шаг 1 % суток меняет
	# веса мало (нет «щёлка» неба в момент заката).
	var before := DayMath.palette_mixes(B.day_cycle_sec * (B.day_share - 0.01))
	var after := DayMath.palette_mixes(B.day_cycle_sec * B.day_share)
	assert_almost_eq(before.y, 0.0, 0.01, "у границы дня дневная доля ~0")
	assert_almost_eq(after.y, 0.0, EPS, "за границей дня дневной доли нет")
	assert_almost_eq(before.w, after.w, 0.01, "ночная доля непрерывна")


func test_palette_mixes_seam_continuous() -> void:
	# Шов суток (П5.9 блок 6): полночь лежит внутри плавного перехода
	# ночь → рассвет, веса непрерывны через границу цикла — нет «щёлка»
	# неба в момент заворачивания часов.
	assert_almost_eq(
		DayMath.palette_mixes(0.0).x, 1.0, EPS,
		"начало суток — чистая палитра рассвета",
	)
	var before_seam := DayMath.palette_mixes(B.day_cycle_sec * (1.0 - 1.0 / 600.0))
	var after_seam := DayMath.palette_mixes(B.day_cycle_sec * (1.0 / 600.0))
	assert_almost_eq(
		before_seam.x + before_seam.w, 1.0, EPS, "у шва только рассвет и ночь"
	)
	assert_almost_eq(
		after_seam.x + after_seam.y, 1.0, EPS, "после шва — рассвет и день"
	)
	assert_almost_eq(
		after_seam.x, before_seam.x, 0.02, "доля рассвета непрерывна через шов"
	)
	assert_almost_eq(
		after_seam.w, before_seam.w, 0.02, "доля ночи непрерывна через шов"
	)
