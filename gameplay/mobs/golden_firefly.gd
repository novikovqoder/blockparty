# Золотой светлячок (раздел 8 SPEC): парит в чаще леса с мягкими вспышками.
# Уязвим только от ударов двух разных игроков в пределах 3 с — окно и пару
# решает хост (ActivityAuthority.try_firefly_hit, П5), узел мигает ярче,
# пока окно открыто. Возрождение — 300 с. Модель (раздел 16): светящаяся
# сфера с роем частиц и glow (Environment).
class_name GoldenFirefly
extends Mob

@export var motion: Dictionary = {}

var _core: MeshInstance3D
var _core_material: StandardMaterial3D
var _light: OmniLight3D
## Конец окна уязвимости по world_time (после первого удара, ≤ 0 — закрыто).
var _weaken_until: float = -1.0


func _ready() -> void:
	super()
	EventBus.firefly_weakened.connect(_on_firefly_weakened)


func _on_firefly_weakened(weakened_id: int, _peer: int, until: float) -> void:
	if weakened_id == spawn_id:
		_weaken_until = until


func _apply_motion(world_time: float) -> void:
	position = MobMotion.firefly_position(motion, world_time)
	var glow: float = MobMotion.firefly_glow(motion, world_time)
	# Окно уязвимости: светлячок вспыхивает — второй игрок видит, что
	# добивающий удар сейчас засчитается (раздел 8).
	if world_time < _weaken_until:
		glow = maxf(glow, 0.9)
	if _light != null:
		_light.light_energy = 0.15 + 0.5 * glow
	if _core_material != null:
		_core_material.emission_energy_multiplier = 0.8 + 1.6 * glow


func position_at(world_time: float) -> Vector3:
	return MobMotion.firefly_position(motion, world_time)


func reward() -> int:
	return B.firefly_reward


func respawn_sec() -> float:
	return B.firefly_respawn_sec


func hitbox_size() -> Vector3:
	return Vector3(0.5, 0.5, 0.5)


func poof_color() -> Color:
	return PAL.firefly


func _build() -> void:
	_core = MeshInstance3D.new()
	_core.name = "Core"
	var sphere := SphereMesh.new()
	sphere.radius = 0.14
	sphere.height = 0.28
	_core.mesh = sphere
	_core_material = StandardMaterial3D.new()
	_core_material.albedo_color = PAL.firefly
	_core_material.emission_enabled = true
	_core_material.emission = PAL.firefly
	_core_material.emission_energy_multiplier = 1.2
	_core.material_override = _core_material
	add_child(_core)
	# Рой золотых искр вокруг (мигает вместе с ядром).
	var sparkles := GPUParticles3D.new()
	sparkles.name = "Sparkles"
	sparkles.amount = 16
	sparkles.lifetime = 1.1
	sparkles.emitting = true
	sparkles.explosiveness = 0.0
	sparkles.visibility_range_end = 60.0
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0, 1, 0)
	process.spread = 180.0
	process.initial_velocity_min = 0.1
	process.initial_velocity_max = 0.35
	process.gravity = Vector3.ZERO
	process.scale_min = 0.4
	process.scale_max = 0.9
	sparkles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	var quad_material := StandardMaterial3D.new()
	quad_material.albedo_color = PAL.firefly
	quad_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad_material.emission_enabled = true
	quad_material.emission = PAL.firefly
	quad_material.emission_energy_multiplier = 2.0
	quad.material = quad_material
	sparkles.draw_pass_1 = quad
	add_child(sparkles)
	_light = OmniLight3D.new()
	_light.light_color = PAL.firefly
	_light.omni_range = 6.0
	_light.light_energy = 0.4
	add_child(_light)
