# Птица (раздел 8 SPEC): кружит над лесом и холмами на высоте 2–4 м, один
# удар — падает и даёт монету, возрождается через 180 с (Balance). Машет
# крыльями (визуал — от часов мира, детерминировано).
class_name Bird
extends Mob

@export var motion: Dictionary = {}

var _model: Node3D
var _wings: Array[MeshInstance3D] = []


func _apply_motion(world_time: float) -> void:
	position = MobMotion.bird_position(motion, world_time)
	_model.rotation.y = MobMotion.bird_yaw(motion, world_time)
	var flap: float = sin(world_time * 9.0) * 0.6
	for side: int in _wings.size():
		_wings[side].rotation.z = (-1.0 if side == 0 else 1.0) * flap


func position_at(world_time: float) -> Vector3:
	return MobMotion.bird_position(motion, world_time)


func reward() -> int:
	return B.bird_reward


func hitbox_size() -> Vector3:
	return Vector3(1.2, 0.6, 1.2)


func _build() -> void:
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	_box(Vector3(0.5, 0.35, 0.7), Vector3.ZERO, PAL.bird, _model)
	_box(Vector3(0.16, 0.16, 0.16), Vector3(0.0, 0.1, 0.42), PAL.coin, _model)
	_box(Vector3(0.3, 0.08, 0.3), Vector3(0.0, 0.05, -0.45), PAL.bird, _model)
	_wings.append(_box(Vector3(0.55, 0.08, 0.35), Vector3(-0.5, 0.08, 0.0), PAL.bird, _model))
	_wings.append(_box(Vector3(0.55, 0.08, 0.35), Vector3(0.5, 0.08, 0.0), PAL.bird, _model))
