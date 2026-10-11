# Тесты математики цикла дня (раздел 7, этап П2): сутки 20 минут, день 60%,
# мягкая светлая ночь. Чистые функции DayMath — проверяются периодичность,
# границы дня/ночи, положение солнца и энергия (числа — в Balance).
extends GutTest

const B: Balance = preload("res://gameplay/balance.tres")

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
	# небо не чернеет полностью.
	for t: float in [B.day_cycle_sec * 0.7, B.day_cycle_sec * 0.9]:
		assert_gt(DayMath.ambient_energy(t), 0.15, "ambient ночи не ниже 0.16")
		var top := DayMath.sky_top_color(t)
		assert_gt(top.v, 0.05, "ночное небо не чёрное")
	assert_almost_eq(DayMath.ambient_energy(B.day_cycle_sec * 0.7), 0.16, EPS)


func test_dayness_and_warmth() -> void:
	assert_almost_eq(DayMath.dayness(0.0), 0.0, EPS, "рассвет — день ещё не полный")
	assert_almost_eq(DayMath.warmth(0.0), 1.0, EPS, "у горизонта — тёплый тон")
	# Полдень: день полный, теплоты нет.
	assert_almost_eq(DayMath.dayness(B.day_cycle_sec * 0.3), 1.0, 0.01)
	assert_almost_eq(DayMath.warmth(B.day_cycle_sec * 0.3), 0.0, 0.01)
	assert_almost_eq(DayMath.dayness(B.day_cycle_sec * 0.7), 0.0, EPS, "ночью dayness 0")


func test_horizon_warms_at_sunrise() -> void:
	# У рассвета горизонт теплее полуденного: примесь HORIZON_WARM делает
	# красный выше синего, полдень — холодный (синий выше красного).
	var sunrise := DayMath.horizon_color(B.day_cycle_sec * 0.01)
	var noon := DayMath.horizon_color(B.day_cycle_sec * 0.3)
	assert_gt(sunrise.r - sunrise.b, 0.0, "рассвет тёплый (r > b)")
	assert_gt(noon.b - noon.r, 0.0, "полдень холодный (b > r)")
	assert_gt(
		(sunrise.r - sunrise.b) - (noon.r - noon.b), 0.0,
		"рассвет теплее полудня",
	)


func test_sky_mixes_sum_to_one_all_day() -> void:
	# П5.7 блок 3: веса панорам (день, закат, ночь) в сумме дают единицу
	# в любой точке суток — небо не чернеет и не пересвечивается.
	var step: float = B.day_cycle_sec / 60.0
	for i: int in range(60):
		var t: float = step * i
		var mixes := DayMath.sky_mixes(t)
		assert_almost_eq(mixes.x + mixes.y + mixes.z, 1.0, EPS,
			"сумма весов панорам = 1 (t=%.1f)" % t)
		assert_between(mixes.x, 0.0, 1.0, "вес дня корректен (t=%.1f)" % t)
		assert_between(mixes.y, 0.0, 1.0, "вес заката корректен (t=%.1f)" % t)
		assert_between(mixes.z, 0.0, 1.0, "вес ночи корректен (t=%.1f)" % t)


func test_sky_mixes_phases() -> void:
	# Полдень — чистый день, полночь — чистая ночь; закат (0.58 суток,
	# солнце низко) замешан из тёплой панорамы и нарастающей ночи —
	# переход плавный, без скачка на границе дня.
	var noon := DayMath.sky_mixes(B.day_cycle_sec * 0.3)
	assert_almost_eq(noon.x, 1.0, 0.01, "полдень — панорама дня")
	assert_almost_eq(noon.z, 0.0, EPS, "ночную панораму не видно")
	var midnight := DayMath.sky_mixes(B.day_cycle_sec * 0.8)
	assert_almost_eq(midnight.z, 1.0, EPS, "полночь — панорама ночи")
	var sunset := DayMath.sky_mixes(B.day_cycle_sec * 0.58)
	assert_gt(sunset.y, noon.y + 0.1, "закат теплее полудня (dusk_mix вырос)")
	assert_gt(sunset.y, sunset.x, "закатная панорама сильнее дневной")
	assert_between(sunset.z, 0.0, 0.9, "закат ещё не ночь (ночь < 0.9)")
	# Смешивание непрерывно на границе дня и ночи: шаг 1 % суток меняет
	# веса мало (нет «щёлка» неба в момент заката).
	var before := DayMath.sky_mixes(B.day_cycle_sec * (B.day_share - 0.01))
	var after := DayMath.sky_mixes(B.day_cycle_sec * B.day_share)
	assert_almost_eq(before.x, 0.0, 0.01, "у границы дня дневная доля ~0")
	assert_almost_eq(after.x, 0.0, EPS, "за границей дня дневной доли нет")
	assert_almost_eq(before.z, after.z, 0.01, "ночная доля непрерывна")


func test_sky_yaw_follows_sun() -> void:
	# Поворот панорамы согласован с азимутом солнца: у полудня и заката
	# разница поворотов равна разнице азимутов (панорама едет за солнцем).
	var noon_yaw := DayMath.sky_yaw(B.day_cycle_sec * 0.3)
	var sunset_yaw := DayMath.sky_yaw(B.day_cycle_sec * 0.58)
	var noon_dir := DayMath.sun_direction(B.day_cycle_sec * 0.3)
	var sunset_dir := DayMath.sun_direction(B.day_cycle_sec * 0.58)
	var dnoon := atan2(noon_dir.x, noon_dir.z)
	var dsunset := atan2(sunset_dir.x, sunset_dir.z)
	assert_almost_eq(
		noon_yaw - sunset_yaw, dsunset - dnoon, 0.01,
		"панорама повёрнута на разницу азимутов солнца",
	)
