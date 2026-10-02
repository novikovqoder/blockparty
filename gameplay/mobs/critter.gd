# Зверёк (раздел 8 SPEC): бродит замкнутым маршрутом по земле (луг у площади
# и берег озера), один удар — «испуган», даёт монету, возрождается через 180 с
# (Balance). Маршрут и скорость — из данных острова, траектория чистая.
class_name Critter
extends Mob

@export var motion: Dictionary = {}

var _model: Node3D


func _apply_motion(world_time: float) -> void:
	position = MobMotion.critter_position(motion, world_time)
	_model.rotation.y = MobMotion.critter_yaw(motion, world_time)


func reward() -> int:
	return B.critter_reward


func hitbox_size() -> Vector3:
	return Vector3(0.7, 1.0, 1.1)


func _build() -> void:
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	_box(Vector3(0.55, 0.4, 0.75), Vector3(0.0, 0.32, 0.0), PAL.critter, _model)
	_box(Vector3(0.35, 0.32, 0.35), Vector3(0.0, 0.62, 0.4), PAL.critter, _model)
	_box(Vector3(0.1, 0.22, 0.06), Vector3(-0.1, 0.86, 0.4), PAL.critter, _model)
	_box(Vector3(0.1, 0.22, 0.06), Vector3(0.1, 0.86, 0.4), PAL.critter, _model)
	_box(Vector3(0.12, 0.12, 0.35), Vector3(0.0, 0.4, -0.5), PAL.critter, _model)
	_box(Vector3(0.1, 0.1, 0.1), Vector3(-0.18, 0.14, 0.35), PAL.critter, _model)
	_box(Vector3(0.1, 0.1, 0.1), Vector3(0.18, 0.14, 0.35), PAL.critter, _model)
