# Математика цикла дня (раздел 7 SPEC): сутки 20 минут, день 60% / ночь 40%,
# мягкая светлая ночь. Чистые функции от часов мира — DayCycle применяет их
# к солнцу, небу и туману, тесты GUT проверяют периодичность и границы.
# Все константы — Balance (day_cycle_sec, day_share, sun_*).
class_name DayMath
extends RefCounted

const B: Balance = preload("res://gameplay/balance.tres")

## Доля переходов между временами суток (П5.9 блок 6): рассвет перетекает
## в день за 30 % дневного отрезка, закат в ночь — за 30 % ночного.
const PHASE_BLEND: float = 0.30


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


## Энергия ambient-освещения (небо): ночь мягкая и светлая — не ниже 0.16.
static func ambient_energy(world_time: float) -> float:
	return 0.16 + 0.36 * dayness(world_time)


## Высота солнца в долях: днём sin(π·прогресса дня) [0..1], ночью —
## отрицательная глубина −sin(π·прогресса ночи) [−1..0]. На рассвете
## и закате ровно ноль — функция непрерывна через границу суток (нет
## «щёлчка» неба в момент ухода солнца).
static func sun_height(world_time: float) -> float:
	var h := sin(PI * phase_progress(world_time))
	return h if is_day(world_time) else -h


## Веса палитр времён суток (П5.9 блок 6): (рассвет, день, закат, ночь),
## сумма 1 в любой точке суток. Рассвет — начало суток (доля 0), закат —
## граница day_share; переходы плавные и непрерывны, включая шов полуночи:
## конец ночи перетекает в рассвет так же, как рассвет в день. Небо и туман
## красятся смешением этих весов по VisualPalette.
static func palette_mixes(world_time: float) -> Vector4:
	var f := day_fraction(world_time)
	var day := B.day_share
	var night := 1.0 - day
	var dawn_end := day * PHASE_BLEND
	var day_end := day * (1.0 - PHASE_BLEND)
	var dusk_end := day + night * PHASE_BLEND
	var night_end := 1.0 - night * PHASE_BLEND
	var dawn: float
	var full_day: float
	var dusk: float
	var full_night: float
	if f < dawn_end:
		# Рассвет → день.
		var w := smoothstep(0.0, 1.0, f / dawn_end)
		dawn = 1.0 - w
		full_day = w
		dusk = 0.0
		full_night = 0.0
	elif f < day_end:
		dawn = 0.0
		full_day = 1.0
		dusk = 0.0
		full_night = 0.0
	elif f < day:
		# День → закат.
		var w := smoothstep(0.0, 1.0, (f - day_end) / (day - day_end))
		dawn = 0.0
		full_day = 1.0 - w
		dusk = w
		full_night = 0.0
	elif f < dusk_end:
		# Закат → ночь.
		var w := smoothstep(0.0, 1.0, (f - day) / (dusk_end - day))
		dawn = 0.0
		full_day = 0.0
		dusk = 1.0 - w
		full_night = w
	elif f < night_end:
		dawn = 0.0
		full_day = 0.0
		dusk = 0.0
		full_night = 1.0
	else:
		# Ночь → рассвет (шов суток).
		var w := smoothstep(0.0, 1.0, (f - night_end) / (1.0 - night_end))
		dawn = w
		full_day = 0.0
		dusk = 0.0
		full_night = 1.0 - w
	return Vector4(dawn, full_day, dusk, full_night)
