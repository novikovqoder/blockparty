# Цикл дня (раздел 7 SPEC): ведёт солнце, небо и туман по часам мира
# (Session.world_time — у всех одинаково, от хоста). Вся математика — чистые
# функции DayMath, числа — Balance; нода создаётся сценой мира (setup со
# ссылками на Sun и WorldEnvironment, напрямую сцены друг друга не знают).
class_name DayCycle
extends Node3D

const B: Balance = preload("res://gameplay/balance.tres")
const PAL: Palette = preload("res://assets/palette.tres")

## Доля зонного цвета в тумане (раздел 16: «туман по зонам»): 0.45 — оттенок
## зоны читается, но время суток остаётся главным.
const ZONE_FOG_MIX: float = 0.45
## Цвет солнца: нейтрально-тёплый днём и оранжевый у горизонта (раздел 16:
## «цвет солнца тёплый утром и вечером»).
const SUN_NOON := Color(1.0, 0.97, 0.92)
const SUN_WARM := Color(1.0, 0.68, 0.45)
## Ambient (заполняющий свет неба): холодноватая ночь и тёплый нейтральный
## день — «тональная коррекция в тёплую сторону» (шаг 4 П4.5) сделана самим
## светом, без LUT-текстуры цветокоррекции.
const AMBIENT_NIGHT := Color(0.50, 0.58, 0.72)
const AMBIENT_DAY := Color(0.82, 0.80, 0.76)
## Облака (vfx-fix, блок в): белый день, тёплый закат, приглушённая ночь.
const CLOUD_DAY := Color(1.0, 1.0, 1.0)
const CLOUD_SUNSET := Color(1.0, 0.74, 0.58)
const CLOUD_NIGHT := Color(0.30, 0.36, 0.50)

var _sun: DirectionalLight3D
var _environment: Environment
## Небо-шейдер (облака, солнце); с ProceduralSkyMaterial (старые сцены
## и тесты) — просто без облаков, цвета ведёт как раньше.
var _sky_shader: ShaderMaterial
var _sky_procedural: ProceduralSkyMaterial

## «Простая графика» (раздел 15): туман плотнее — мир меньше на вид.
var simple: bool = false

var _fog_focus: Vector3 = Vector3.ZERO
var _fog_focus_set: bool = false


func setup(sun: DirectionalLight3D, world_env: WorldEnvironment) -> void:
	_sun = sun
	_environment = world_env.environment
	_sky_shader = _environment.sky.sky_material as ShaderMaterial
	_sky_procedural = _environment.sky.sky_material as ProceduralSkyMaterial


## Куда «смотрит» туман: цвет зоны в этой точке подмешивается к туману.
## Сцена мира передаёт позицию игрока каждый кадр (раздел 16).
func set_fog_focus(pos: Vector3) -> void:
	_fog_focus = pos
	_fog_focus_set = true


func _process(_delta: float) -> void:
	if _sun == null:
		return
	var world_time := Session.world_time
	# Свет идёт от солнца: −Z солнца смотрит от него.
	var to_sun := DayMath.sun_direction(world_time)
	_sun.basis = Basis.looking_at(-to_sun, Vector3.UP)
	_sun.light_energy = DayMath.sun_energy(world_time)
	_sun.light_color = SUN_NOON.lerp(SUN_WARM, DayMath.warmth(world_time))
	var horizon := DayMath.horizon_color(world_time)
	var top := DayMath.sky_top_color(world_time)
	var warmth := DayMath.warmth(world_time)
	var dayness := DayMath.dayness(world_time)
	# Небо (vfx-fix, блок в): шейдер — градиент, облака, солнце;
	# ProceduralSkyMaterial — прежние цвета без облаков.
	if _sky_shader != null:
		_sky_shader.set_shader_parameter("top_color", top)
		_sky_shader.set_shader_parameter("horizon_color", horizon)
		_sky_shader.set_shader_parameter("ground_color", top.darkened(0.3))
		_sky_shader.set_shader_parameter("sun_direction", to_sun)
		_sky_shader.set_shader_parameter("sun_color", _sun.light_color)
		var cloud := CLOUD_NIGHT.lerp(CLOUD_DAY, dayness)
		_sky_shader.set_shader_parameter(
			"cloud_color", cloud.lerp(CLOUD_SUNSET, warmth * 0.65))
		# Количество облаков медленно дышит по часам мира — небо живое.
		_sky_shader.set_shader_parameter(
			"cloud_cover", 0.32 + 0.10 * sin(world_time * 0.008))
	elif _sky_procedural != null:
		_sky_procedural.sky_top_color = top
		_sky_procedural.sky_horizon_color = horizon
		_sky_procedural.ground_horizon_color = horizon
		_sky_procedural.ground_bottom_color = top.darkened(0.3)
	_environment.ambient_light_energy = DayMath.ambient_energy(world_time)
	_environment.ambient_light_color = AMBIENT_NIGHT.lerp(
		AMBIENT_DAY, dayness
	)
	# Закат (vfx-fix, блок в): солнце низкое — тени длинные; при низком
	# солнце они ещё и мягче обычного (blur растёт к горизонту).
	_sun.shadow_blur = 1.4 + warmth * 0.8
	_environment.fog_light_color = horizon
	if _fog_focus_set:
		# Туман по зонам (раздел 16): цвет зоны игрока поверх цвета горизонта.
		var zone_fog := IslandGen.zone_blend(
			Vector2(_fog_focus.x, _fog_focus.z), PAL.zone_fog
		)
		_environment.fog_light_color = horizon.lerp(zone_fog, ZONE_FOG_MIX)
	_environment.fog_density = B.fog_density_simple if simple else B.fog_density
	# Дымка по высоте (раздел 16): низины и вода — в лёгкой дымке.
	_environment.fog_height = B.fog_height_m
	_environment.fog_height_density = B.fog_height_density
