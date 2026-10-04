# Птица (раздел 8 SPEC): кружит над лесом и холмами на высоте 2–4 м, один
# удар — падает и даёт монету, возрождается через 180 с (Balance). Машет
# крыльями (визуал — от часов мира, детерминировано). Модель (раздел 16):
# огранённое тело-призма, треугольные крылья, общий шейдер lowpoly.
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


func poof_color() -> Color:
	return PAL.bird


func _build() -> void:
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	# Тело-призма: гранёный «боб» вдоль полёта (+Z), узкое к хвосту.
	var body := CylinderMesh.new()
	body.radial_segments = 5
	body.top_radius = 0.09
	body.bottom_radius = 0.2
	body.height = 0.7
	_lowpoly(body, Vector3(0, 0, -0.05), PAL.bird, _model, Vector3(PI / 2.0, 0, 0))
	# Голова — огранённая сферка и конический клюв.
	var head := SphereMesh.new()
	head.radial_segments = 5
	head.rings = 1
	head.radius = 0.15
	head.height = 0.3
	_lowpoly(head, Vector3(0, 0.09, 0.3), PAL.bird, _model)
	var beak := CylinderMesh.new()
	beak.radial_segments = 4
	beak.top_radius = 0.0
	beak.bottom_radius = 0.05
	beak.height = 0.2
	_lowpoly(beak, Vector3(0, 0.06, 0.45), PAL.coin, _model, Vector3(PI / 2.0, 0, 0))
	# Хвост — треугольный веер.
	var tail := PrismMesh.new()
	tail.size = Vector3(0.3, 0.05, 0.3)
	_lowpoly(tail, Vector3(0, 0.02, -0.48), PAL.bird.darkened(0.12), _model)
	# Крылья: треугольные пластины (машут — rotation.z в _apply_motion).
	for side: float in [-1.0, 1.0]:
		var wing := PrismMesh.new()
		wing.size = Vector3(0.62, 0.04, 0.34)
		_wings.append(_lowpoly(
			wing, Vector3(0.36 * side, 0.08, 0.0), PAL.bird, _model,
			Vector3(PI / 2.0, 0, 0)))
