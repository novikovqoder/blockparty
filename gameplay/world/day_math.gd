# Математика цикла дня (раздел 7 SPEC): сутки 20 минут, день 60% / ночь 40%,
# мягкая светлая ночь. Чистые функции от часов мира — DayCycle применяет их
# к солнцу, небу и туману, тесты GUT проверяют периодичность и границы.
# Все константы — Balance (day_cycle_sec, day_share, sun_*).
class_name DayMath
extends RefCounted

const B: Balance = preload("res://gameplay/balance.tres")

## Палитра неба: верх / горизонт для дня, ночи и тёплой полосы у горизонта
## на рассвете и закате (раздел 16: мягкие пастельные тона).
const SKY_TOP_DAY := Color(0.44, 0.64, 0.85)
const SKY_TOP_NIGHT := Color(0.07, 0.11, 0.21)
const HORIZON_DAY := Color(0.74, 0.83, 0.9)
const HORIZON_NIGHT := Color(0.22, 0.27, 0.38)
const HORIZON_WARM := Color(1.0, 0.62, 0.38)


## Доля суток [0, 1): 0 — рассвет, day_share — закат, далее ночь.
static func day_fraction(world_time: float) -> float:
	return fposmod(world_time, B.day_cycle_sec) / B.day_cycle_sec


## День ли (солнце над горизонтом).
static func is_day(world_time: float) -> bool:
	return day_fraction(world_time) < B.day_share


## Прогресс дня [0, 1]: 0 — рассвет, 1 — закат (ночью — прогресс ночи).
static func phase_progress(world_time: float) -> float:
	var f := day_fraction(world_time)
	if f < B.day_share:
		return f / B.day_share
	return (f - B.day_share) / (1.0 - B.day_share)


## Направление НА солнце (нормализованный вектор): днём — дуга от востока
## через юг на запад (высота синусом, максимум sun_max_elevation), ночью —
## «солнце под горизонтом» (свет выключен, но вектор оставлен корректным).
static func sun_direction(world_time: float) -> Vector3:
	var day := is_day(world_time)
	var progress := phase_progress(world_time)
	var elevation: float
	var azimuth: float
	if day:
		elevation = sin(PI * progress) * B.sun_max_elevation
		azimuth = lerpf(-B.sun_azimuth_swing, B.sun_azimuth_swing, progress)
	else:
		# Ночь: солнце ушло под горизонт и медленно возвращается к рассвету.
		elevation = lerpf(-0.35, -0.05, progress)
		azimuth = lerpf(B.sun_azimuth_swing, -B.sun_azimuth_swing, progress)
	return Vector3(
		sin(azimuth) * cos(elevation),
		sin(elevation),
		cos(azimuth) * cos(elevation),
	).normalized()


## Энергия солнца: рассвет/закат ~треть полуденной, ночью ноль (небо светит
## само — ambient, мягкая ночь раздела 7).
static func sun_energy(world_time: float) -> float:
	if not is_day(world_time):
		return 0.0
	var height := sin(PI * phase_progress(world_time))
	return B.sun_energy_noon * (0.35 + 0.65 * height)


## Насколько «полный день» [0, 1] — для цвета неба и ambient.
static func dayness(world_time: float) -> float:
	if not is_day(world_time):
		return 0.0
	return clampf(sin(PI * phase_progress(world_time)) * 2.2, 0.0, 1.0)


## Насколько близко к горизонту солнце [0, 1] — тёплые рассвет и закат.
static func warmth(world_time: float) -> float:
	if not is_day(world_time):
		return 0.0
	return 1.0 - clampf(sin(PI * phase_progress(world_time)) * 3.0, 0.0, 1.0)


static func sky_top_color(world_time: float) -> Color:
	return SKY_TOP_NIGHT.lerp(SKY_TOP_DAY, dayness(world_time))


static func horizon_color(world_time: float) -> Color:
	var base: Color = HORIZON_NIGHT.lerp(HORIZON_DAY, dayness(world_time))
	return base.lerp(HORIZON_WARM, warmth(world_time) * 0.85)


## Энергия ambient-освещения (небо): ночь мягкая и светлая — не ниже 0.16.
static func ambient_energy(world_time: float) -> float:
	return 0.16 + 0.36 * dayness(world_time)
