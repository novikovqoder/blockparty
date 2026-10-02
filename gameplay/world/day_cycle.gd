# Цикл дня (раздел 7 SPEC): ведёт солнце, небо и туман по часам мира
# (Session.world_time — у всех одинаково, от хоста). Вся математика — чистые
# функции DayMath, числа — Balance; нода создаётся сценой мира (setup со
# ссылками на Sun и WorldEnvironment, напрямую сцены друг друга не знают).
class_name DayCycle
extends Node3D

const B: Balance = preload("res://gameplay/balance.tres")

var _sun: DirectionalLight3D
var _environment: Environment
var _sky: ProceduralSkyMaterial

## «Простая графика» (раздел 15): туман плотнее — мир меньше на вид.
var simple: bool = false


func setup(sun: DirectionalLight3D, world_env: WorldEnvironment) -> void:
	_sun = sun
	_environment = world_env.environment
	_sky = _environment.sky.sky_material as ProceduralSkyMaterial


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
	_environment.fog_density = B.fog_density_simple if simple else B.fog_density
