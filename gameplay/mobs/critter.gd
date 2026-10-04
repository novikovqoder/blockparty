# Зверёк (раздел 8 SPEC): бродит замкнутым маршрутом по земле (луг у площади
# и берег озера), один удар — «испуган», даёт монету, возрождается через 180 с
# (Balance). Маршрут и скорость — из данных острова, траектория чистая.
# Модель (раздел 16): округлый, сглаженный, с длинными ушами — как
# персонажи-«мармеладки», обычный материал.
class_name Critter
extends Mob

@export var motion: Dictionary = {}

var _model: Node3D


func _apply_motion(world_time: float) -> void:
	position = MobMotion.critter_position(motion, world_time)
	_model.rotation.y = MobMotion.critter_yaw(motion, world_time)


func position_at(world_time: float) -> Vector3:
	return MobMotion.critter_position(motion, world_time)


func reward() -> int:
	return B.critter_reward


func hitbox_size() -> Vector3:
	return Vector3(0.7, 1.0, 1.1)


func poof_color() -> Color:
	return PAL.critter


func _build() -> void:
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	var body_color: Color = PAL.critter
	# Тело — округлая «груша», чуть присевшая.
	var body := SphereMesh.new()
	body.radius = 0.3
	body.height = 0.6
	var body_mesh := _smooth(body, Vector3(0, 0.3, 0), body_color, _model)
	body_mesh.scale = Vector3(1.0, 0.88, 1.15)
	# Голова — сфера с длинными ушами и глазками.
	var head := SphereMesh.new()
	head.radius = 0.2
	head.height = 0.4
	_smooth(head, Vector3(0, 0.55, 0.24), body_color, _model)
	for side: float in [-1.0, 1.0]:
		var ear := CapsuleMesh.new()
		ear.radius = 0.045
		ear.height = 0.34
		_smooth(
			ear, Vector3(0.09 * side, 0.82, 0.18), body_color.darkened(0.08), _model,
			Vector3(0.16, 0, -0.22 * side))
		var eye := SphereMesh.new()
		eye.radius = 0.032
		eye.height = 0.064
		_smooth(eye, Vector3(0.08 * side, 0.6, 0.42), PAL.eye, _model)
	# Хвостик-шарик и лапки.
	var tail := SphereMesh.new()
	tail.radius = 0.09
	tail.height = 0.18
	_smooth(tail, Vector3(0, 0.28, -0.4), Color.WHITE.lerp(body_color, 0.4), _model)
	for paw_at: Vector3 in [
		Vector3(-0.14, 0.09, 0.18), Vector3(0.14, 0.09, 0.18),
		Vector3(-0.15, 0.09, -0.16), Vector3(0.15, 0.09, -0.16),
	]:
		var paw := SphereMesh.new()
		paw.radius = 0.075
		paw.height = 0.15
		_smooth(paw, paw_at, body_color.darkened(0.25), _model)
