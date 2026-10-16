# Цикл дня (раздел 7 SPEC): ведёт солнце, луну, звёзды, небо и туман по
# часам мира (Session.world_time — у всех одинаково, от хоста). Вся
# математика — чистые функции DayMath, числа — Balance; нода создаётся
# сценой мира (setup со ссылкой на WorldEnvironment со Sky3D, напрямую
# сцены друг друга не знают).
#
# П5.9 блок 6: небо рисует Sky3D (атмосферное рассеяние, облака, луна,
# звёзды). Его собственный ход времени (TimeOfDay) выключен — часы мира
# сетевые, купол ведёт этот цикл: каждый кадр ставит солнце и луну на
# вычисленные DayMath позиции. Цвета неба, тумана, светил и ambient —
# смешение палитр времён суток (VisualPalette, правится в инспекторе).
# Экранный туман Sky3D не используется: туман и дымку ведёт Environment.
class_name DayCycle
extends Node3D

const B: Balance = preload("res://gameplay/balance.tres")
const PAL: Palette = preload("res://assets/palette.tres")
const VPAL: VisualPalette = preload("res://assets/visual_palette.tres")

## Доля зонного цвета в тумане (раздел 16: «туман по зонам»): 0.45 — оттенок
## зоны читается, но время суток остаётся главным.
const ZONE_FOG_MIX: float = 0.45
## Экспозиция тонемапа ночью (П5.7 блок 3): ночь должна быть «мягкой светлой»
## (раздел 7 SPEC) — поднятая экспозиция оставляет силуэты читаемыми.
const NIGHT_EXPOSURE: float = 1.9
## Наклон звёздного неба (широта наблюдателя): полюс мира заметно над
## горизонтом, звёзды ходят наклонёнными кругами.
const STAR_TILT: float = 0.8
## Затемнение сине-фиолетовой ночи палитры в атмосферном тинте: рассеяние
## добавляет свой вклад, полная хроматика ночи делала бы небо сиреневым.
const NIGHT_TINT_DIM: float = 0.45


var _sun: DirectionalLight3D
var _environment: Environment
## Купол Sky3D (небо, облака, луна, звёзды); Null в сценах без Sky3D —
## тогда цикл ведёт только свет и окружение (тесты, лаборатории света).
var _dome: SkyDome
var _tod: TimeOfDay

## «Простая графика» (раздел 15): туман плотнее — мир меньше на вид.
var simple: bool = false

var _fog_focus: Vector3 = Vector3.ZERO
var _fog_focus_set: bool = false


func setup(sun: DirectionalLight3D, world_env: WorldEnvironment) -> void:
	_sun = sun
	_environment = world_env.environment
	_dome = world_env.get_node_or_null("SkyDome") as SkyDome
	_tod = world_env.get_node_or_null("TimeOfDay") as TimeOfDay
	if _dome == null:
		push_warning("DayCycle: нет SkyDome — небо Sky3D не ведётся")
		return
	# Часы ведёт сеть (Session.world_time), а не TimeOfDay: выключаем его
	# таймер, чтобы он не перезаписывал положения светил своей моделью.
	if _tod != null:
		_tod.game_time_enabled = false
		_tod.editor_time_enabled = false
	# Светила: энергия солнца — из Balance, луна слабая и синеватая из
	# палитры ночи; диск луны чуть приглушён.
	_dome.sun_light_energy = B.sun_energy_noon
	_dome.moon_light_energy = B.moon_energy_night
	_dome.moon_light_color = VPAL.night_sun
	_dome.moon_color = VPAL.night_sun.lightened(0.25)
	_dome.sun_disk_color = VPAL.dusk_sun
	# Облака ночью — сине-фиолетовые из палитры, днём их красит солнце.
	_dome.clouds_night_color = VPAL.night_sky_horizon.darkened(0.35)
	# Экранный туман Sky3D не нужен: туман и дымка — Environment (балансы
	# из Balance, цвет из палитры), у купола своё рассеяние на горизонте.
	_dome.fog_visible = false
	# Звёздное небо: наклон оси, поворот ведём по часам мира в _process.
	_dome.sky_material.set_shader_parameter("star_tilt", STAR_TILT)


## Куда «смотрит» туман: цвет зоны в этой точке подмешивается к туману.
## Сцена мира передаёт позицию игрока каждый кадр (раздел 16).
func set_fog_focus(pos: Vector3) -> void:
	_fog_focus = pos
	_fog_focus_set = true


func _process(_delta: float) -> void:
	if _sun == null:
		return
	var world_time := Session.world_time
	var to_sun := DayMath.sun_direction(world_time)
	var mixes := DayMath.palette_mixes(world_time)
	var warmth := DayMath.warmth(world_time)
	var dayness := DayMath.dayness(world_time)
	# Цвета из палитры (до позиций: обновление купола подхватит их).
	var sun_color := _mix4(VPAL.dawn_sun, VPAL.day_sun, VPAL.dusk_sun,
		VPAL.night_sun, mixes)
	var sky_top := _mix4(VPAL.dawn_sky_top, VPAL.day_sky_top,
		VPAL.dusk_sky_top, VPAL.night_sky_top, mixes)
	var sky_horizon := _mix4(VPAL.dawn_sky_horizon, VPAL.day_sky_horizon,
		VPAL.dusk_sky_horizon, VPAL.night_sky_horizon, mixes)
	_dome.sun_light_color = sun_color
	_dome.sun_horizon_light_color = sun_color.lerp(VPAL.dusk_sun, 0.7 * warmth)
	# Атмосферные тинты — хроматика палитры (яркость неба задаёт модель
	# рассеяния): верх, тёплый низ у горизонта и ночь приглушенной синевой.
	_dome.atm_day_tint = _chroma(sky_top)
	_dome.atm_horizon_light_tint = _chroma(sky_horizon)
	_dome.atm_night_tint = _chroma(VPAL.night_sky_top * NIGHT_TINT_DIM)
	_dome.ground_color = sky_horizon.darkened(0.55)
	# Позиции светил: sun_altitude — полярный угол от зенита (высота − 90°),
	# азимут 0 — север; луна ходит противоположно солнцу и восходит на закате.
	_dome.sun_altitude = acos(clampf(to_sun.y, -1.0, 1.0))
	_dome.sun_azimuth = atan2(to_sun.x, to_sun.z)
	var to_moon := -to_sun
	_dome.moon_altitude = acos(clampf(to_moon.y, -1.0, 1.0))
	_dome.moon_azimuth = atan2(to_moon.x, to_moon.z)
	# Звёзды: полный оборот за сутки мира — небо живёт, привязано к часам.
	_dome.sky_material.set_shader_parameter(
		"star_rotation", TAU * DayMath.day_fraction(world_time))
	# Окружение — палитра поверх того, что выставил купол.
	_environment.ambient_light_color = _mix4(VPAL.dawn_ambient,
		VPAL.day_ambient, VPAL.dusk_ambient, VPAL.night_ambient, mixes)
	_environment.ambient_light_energy = DayMath.ambient_energy(world_time)
	# Ночью экспозиция выше — «мягкая светлая ночь» (глаза адаптировались).
	_environment.tonemap_exposure = lerpf(NIGHT_EXPOSURE, 1.0, dayness)
	# Солнце низкое — тени длинные; у горизонта они ещё и мягче (blur растёт).
	_sun.shadow_blur = 1.4 + warmth * 0.8
	# Туман — цвет палитры времени суток, поверх — оттенок зоны игрока.
	var fog := _mix4(VPAL.dawn_fog, VPAL.day_fog, VPAL.dusk_fog,
		VPAL.night_fog, mixes)
	if _fog_focus_set:
		# Туман по зонам (раздел 16): цвет зоны игрока поверх палитры.
		var zone_fog := IslandGen.zone_blend(
			Vector2(_fog_focus.x, _fog_focus.z), PAL.zone_fog
		)
		fog = fog.lerp(zone_fog, ZONE_FOG_MIX)
	_environment.fog_light_color = fog
	_environment.fog_density = B.fog_density_simple if simple else B.fog_density
	# Дымка по высоте (раздел 16): низины и вода — в лёгкой дымке.
	_environment.fog_height = B.fog_height_m
	_environment.fog_height_density = B.fog_height_density


## Смешение четырёх цветов палитры по весам времён суток.
func _mix4(a: Color, b: Color, c: Color, d: Color, w: Vector4) -> Color:
	return Color(
		a.r * w.x + b.r * w.y + c.r * w.z + d.r * w.w,
		a.g * w.x + b.g * w.y + c.g * w.z + d.g * w.w,
		a.b * w.x + b.b * w.y + c.b * w.z + d.b * w.w,
	)


## Хроматика цвета: тон без яркости (максимальный канал = 1) — для тинтов
## атмосферы, где силу света задаёт модель рассеяния.
func _chroma(color: Color) -> Color:
	var peak := maxf(color.r, maxf(color.g, color.b))
	if peak < 0.001:
		return Color.WHITE
	return color / peak
