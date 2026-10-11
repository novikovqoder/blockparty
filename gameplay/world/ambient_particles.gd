# Атмосферные частицы (vfx-fix, визуальный блок г): светлячки в Лесу
# вечером и ночью, пыльца над Площадью днём, листья в Лесу днём. Три
# дешёвых GPUParticles3D; поле частиц следует за игроком (эмиттер
# снапится к сетке — частицы в локальных координатах остаются на местах
# мира), видимость — по зоне и времени суток (DayMath по Session.world_time).
# «Простая графика» — всё выключено (тише); «Высокое качество» — чуть
# плотнее светлячки и пыльца. В headless частицы не тикают, но создаются.
class_name AmbientParticles
extends Node3D

const PAL: Palette = preload("res://assets/palette.tres")

## Центры и радиусы зон (IslandGen.ZONES): лес и площадь.
const FOREST_CENTER := Vector2(-52.0, -52.0)
const FOREST_RADIUS := 44.0
const PLAZA_CENTER := Vector2(0.0, 4.0)
const PLAZA_RADIUS := 20.0
## Поле частиц вокруг игрока, м (эмиттер), и шаг снапа позиции, м.
const FIELD := Vector3(36.0, 6.0, 36.0)
const SNAP: float = 4.0

var _fireflies: GPUParticles3D
var _pollen: GPUParticles3D
var _leaves: GPUParticles3D
var _simple: bool = false
var _focus: Vector3 = Vector3.ZERO


## Создать системы под уровень графики (GraphicsQuality.Tier).
func setup(tier: int) -> void:
	_simple = tier == GraphicsQuality.Tier.SIMPLE
	var density := 1.5 if tier == GraphicsQuality.Tier.HIGH else 1.0
	_fireflies = _make(int(48.0 * density), PAL.firefly, 0.16, 7.0, 0.0, true)
	var fire_process := _fireflies.process_material as ParticleProcessMaterial
	fire_process.initial_velocity_min = 0.2
	fire_process.initial_velocity_max = 0.8
	# Мерцание через color_ramp НЕ используем: GradientTexture1D в
	# Compatibility-рендере глушит частицы до полной невидимости
	# (проверено попиксельным сравнением кадров). Аддитивное свечение
	# без рампа работает в обоих рендерах; glow (блок е) подхватит.

	_pollen = _make(int(34.0 * density), Color(1.0, 0.97, 0.82, 0.78), 0.09, 9.0)
	var pollen_process := _pollen.process_material as ParticleProcessMaterial
	pollen_process.gravity = Vector3(0.25, -0.12, 0.15)
	pollen_process.initial_velocity_min = 0.05
	pollen_process.initial_velocity_max = 0.25
	pollen_process.turbulence_enabled = true
	pollen_process.turbulence_noise_strength = 0.25

	_leaves = _make(
		int(22.0 * density), Color(0.55, 0.67, 0.28, 0.9), 0.09, 11.0)
	var leaves_process := _leaves.process_material as ParticleProcessMaterial
	leaves_process.gravity = Vector3(0, -0.9, 0)
	leaves_process.initial_velocity_min = 0.2
	leaves_process.initial_velocity_max = 0.6
	leaves_process.turbulence_enabled = true
	leaves_process.turbulence_noise_strength = 1.2
	leaves_process.turbulence_noise_scale = 3.0


## Куда стянуть поле частиц (сцена мира передаёт позицию игрока каждый кадр).
func set_focus(pos: Vector3) -> void:
	_focus = pos


func _process(_delta: float) -> void:
	if _fireflies == null:
		return
	global_position = Vector3(
		snappedf(_focus.x, SNAP), 0.0, snappedf(_focus.z, SNAP))
	var day := DayMath.is_day(Session.world_time)
	var flat := Vector2(_focus.x, _focus.z)
	var in_forest: bool = flat.distance_to(FOREST_CENTER) < FOREST_RADIUS
	var in_plaza: bool = flat.distance_to(PLAZA_CENTER) < PLAZA_RADIUS
	_fireflies.emitting = not _simple and in_forest and not day
	_pollen.emitting = not _simple and in_plaza and day
	_leaves.emitting = not _simple and in_forest and day


## Каркас системы: квадратные частицы цвета в объёме FIELD вокруг эмиттера.
func _make(
	amount: int, color: Color, size: float, lifetime: float,
	emission_energy: float = 0.0, additive: bool = false,
) -> GPUParticles3D:
	var fx := GPUParticles3D.new()
	fx.amount = maxi(2, amount)
	fx.lifetime = lifetime
	fx.visibility_aabb = AABB(
		FIELD * -0.6, FIELD * 1.2)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = FIELD * 0.5
	process.direction = Vector3.UP
	process.spread = 180.0
	# Размер задаёт сам квад (в метрах); scale — лёгкая вариативность.
	# НЕ умножать scale на size: он масштабирует квад ещё раз (частица
	# станет миллиметровой и исчезнет с экрана).
	process.scale_min = 0.75
	process.scale_max = 1.0
	fx.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = _particle_mat(color, emission_energy, additive)
	fx.draw_pass_1 = quad
	add_child(fx)
	return fx


## Материал частицы: без освещения, биллборд, цвет и альфа (мерцание
## color_ramp) — из вершинного COLOR; светлячки светятся сами
## (emission_energy > 0).
func _particle_mat(
	color: Color, emission_energy: float, additive: bool,
) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Аддитивное смешивание: светлячки светятся, не гаснут на тёмном фоне.
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission_energy
	return mat
