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

var _sun: DirectionalLight3D
var _environment: Environment
var _sky: ProceduralSkyMaterial

## «Простая графика» (раздел 15): туман плотнее — мир меньше на вид.
var simple: bool = false

var _fog_focus: Vector3 = Vector3.ZERO
var _fog_focus_set: bool = false


func setup(sun: DirectionalLight3D, world_env: WorldEnvironment) -> void:
	_sun = sun
	_environment = world_env.environment
	_sky = _environment.sky.sky_material as ProceduralSkyMaterial


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
	var horizon := DayMath.horizon_color(world_time)
	var top := DayMath.sky_top_color(world_time)
	_sky.sky_top_color = top
	_sky.sky_horizon_color = horizon
	_sky.ground_horizon_color = horizon
	_sky.ground_bottom_color = top.darkened(0.3)
	_environment.ambient_light_energy = DayMath.ambient_energy(world_time)
	_environment.fog_light_color = horizon
	if _fog_focus_set:
		# Туман по зонам (раздел 16): цвет зоны игрока поверх цвета горизонта.
		var zone_fog := IslandGen.zone_blend(
			Vector2(_fog_focus.x, _fog_focus.z), PAL.zone_fog
		)
		_environment.fog_light_color = horizon.lerp(zone_fog, ZONE_FOG_MIX)
	_environment.fog_density = B.fog_density_simple if simple else B.fog_density
