# Финал «Вечернего чая» (П5.5): у костра вскипает чай — пар над огнём
# и светлячки вокруг, пока компания пьёт (quest_firefly_duration, 30 с).
# Масштаб — от числа сидящих, вечером светлячков вдвое больше (ждать
# вечера не нужно: финал наступает, когда мята собрана и игрок сел).
# Всё — процедурные частицы (правило проекта: без ассетов); в headless
# частицы не тикают, но создаются безопасно — логика от них не зависит.
class_name TeaFx
extends Node3D

const B: Balance = preload("res://gameplay/balance.tres")
const PAL: Palette = preload("res://assets/palette.tres")

## Радиус облака светлячков вокруг костра, м.
const FIREFLY_RADIUS: float = 5.5
## Высота полёта светлячков над землёй, м.
const FIREFLY_HEIGHT: float = 1.6
## Сколько секунд после окончания эффекта доживают частицы, с.
const FADE_LINGER: float = 3.0


## Запустить эффект у костра: seated — сколько игроков сейчас сидит
## (масштаб облака), evening — сумерки или ночь (вдвое больше светлячков).
static func spawn(
	parent: Node3D, campfire_pos: Vector3, seated: int, evening: bool
) -> void:
	var fx := TeaFx.new()
	parent.add_child(fx)
	fx.global_position = campfire_pos
	var count: int = (B.quest_firefly_base + B.quest_firefly_per_seated * seated) \
		* (2 if evening else 1)
	fx._run(count)


var _steam: GPUParticles3D
var _flies: GPUParticles3D


func _run(firefly_count: int) -> void:
	_build_steam()
	_build_fireflies(firefly_count)
	var timer := get_tree().create_timer(B.quest_firefly_duration)
	timer.timeout.connect(_stop)


## Пар над огнём: мягкие светлые клубы, медленно вверх.
func _build_steam() -> void:
	_steam = GPUParticles3D.new()
	_steam.name = "Steam"
	_steam.amount = 16
	_steam.lifetime = 2.4
	_steam.position = Vector3(0.0, 0.75, 0.0)
	_steam.local_coords = false
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 12.0
	process.initial_velocity_min = 0.5
	process.initial_velocity_max = 0.9
	process.gravity = Vector3(0.0, 0.25, 0.0)
	process.scale_min = 1.4
	process.scale_max = 3.0
	_steam.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.93, 0.95, 0.97, 0.3)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = material
	_steam.draw_pass_1 = quad
	add_child(_steam)


## Светлячки вокруг костра: облако по сфере, лёгкий дрейф (турбулентность),
## preprocess — облако появляется сразу целиком, а не за 30 с.
func _build_fireflies(count: int) -> void:
	_flies = GPUParticles3D.new()
	_flies.name = "Fireflies"
	_flies.amount = count
	_flies.lifetime = B.quest_firefly_duration
	_flies.preprocess = B.quest_firefly_duration
	_flies.position = Vector3(0.0, FIREFLY_HEIGHT, 0.0)
	_flies.local_coords = false
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = FIREFLY_RADIUS
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = 0.1
	process.initial_velocity_max = 0.35
	process.gravity = Vector3.ZERO
	process.scale_min = 0.6
	process.scale_max = 1.0
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.3
	process.turbulence_noise_scale = 1.2
	_flies.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	var material := StandardMaterial3D.new()
	material.albedo_color = PAL.firefly
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = PAL.firefly
	material.emission_energy_multiplier = 2.4
	quad.material = material
	_flies.draw_pass_1 = quad
	add_child(_flies)


## Время вышло: новые частицы не рождаются, живые доживают и узел уходит.
func _stop() -> void:
	_steam.emitting = false
	_flies.emitting = false
	var timer := get_tree().create_timer(FADE_LINGER)
	timer.timeout.connect(queue_free)
