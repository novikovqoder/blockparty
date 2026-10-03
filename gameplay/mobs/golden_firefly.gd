# Золотой светлячок (раздел 8 SPEC): парит в чаще леса с мягкими вспышками.
# Уязвим только когда рядом двое игроков (раздел 8) — кооп-механика П5,
# поэтому take_hit здесь ничего не делает. Возрождение 300 с наступит в П5.
class_name GoldenFirefly
extends Mob

@export var motion: Dictionary = {}

var _core: MeshInstance3D
var _light: OmniLight3D


func _apply_motion(world_time: float) -> void:
	position = MobMotion.firefly_position(motion, world_time)
	var glow: float = MobMotion.firefly_glow(motion, world_time)
	_light.light_energy = 0.15 + 0.5 * glow
	var material := _core.material_override as StandardMaterial3D
	material.emission_energy_multiplier = 0.8 + 1.2 * glow


func position_at(world_time: float) -> Vector3:
	return MobMotion.firefly_position(motion, world_time)


func is_killable() -> bool:
	return false


func hitbox_size() -> Vector3:
	return Vector3(0.5, 0.5, 0.5)


func _build() -> void:
	_core = _box(Vector3(0.24, 0.24, 0.24), Vector3.ZERO, PAL.firefly, self, 1.0)
	_light = OmniLight3D.new()
	_light.light_color = PAL.firefly
	_light.omni_range = 6.0
	_light.light_energy = 0.4
	add_child(_light)
