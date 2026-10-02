# Камера от третьего лица (раздел 5 SPEC): узел CameraRig (top_level, поэтому
# не наследует повороты персонажа) → Pivot (наклон) → SpringArm3D (столкновение
# с миром, длина 6 м) → Camera3D. Вращение мышью при захваченном курсоре,
## приближение колесом 3–10 м, наклон от −60° до +35°, мягкое следование
# за персонажем. Чувствительность и инверсия оси Y — в Settings (экран
# настроек — П8). Движение персонажа идёт относительно yaw этой камеры.
class_name PlayerCamera
extends Node3D

const B: Balance = preload("res://gameplay/balance.tres")

## Высота точки взгляда над ступнями персонажа, м.
const FOLLOW_HEIGHT: float = 1.35
## Шаг приближения колесом мыши, м.
const ZOOM_STEP: float = 0.5
## Стартовый наклон вниз, рад.
const START_PITCH: float = -0.3

@onready var pivot: Node3D = $Pivot
@onready var arm: SpringArm3D = $Pivot/SpringArm


func _ready() -> void:
	top_level = true
	arm.spring_length = B.camera_length
	pivot.rotation.x = START_PITCH


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var sens: float = B.mouse_base_sensitivity * Settings.mouse_sensitivity
		var invert: float = -1.0 if Settings.camera_invert_y else 1.0
		rotation.y -= motion.relative.x * sens
		pivot.rotation.x = clampf(
			pivot.rotation.x - motion.relative.y * sens * invert,
			deg_to_rad(B.camera_pitch_min_deg),
			deg_to_rad(B.camera_pitch_max_deg),
		)
	elif event is InputEventMouseButton and event.is_pressed():
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(-ZOOM_STEP)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(ZOOM_STEP)


func _physics_process(delta: float) -> void:
	# Мягкое следование за персонажем (родителем, несмотря на top_level).
	var parent := get_parent() as Node3D
	if parent == null:
		return
	var target: Vector3 = parent.global_position + Vector3.UP * FOLLOW_HEIGHT
	global_position = global_position.lerp(
		target, 1.0 - exp(-B.camera_follow_speed * delta)
	)


## Направление взгляда камеры в плоскости земли (для движения персонажа).
func forward_flat() -> Vector3:
	var forward := -global_basis.z
	forward.y = 0.0
	return forward.normalized()


func _zoom(step: float) -> void:
	arm.spring_length = clampf(
		arm.spring_length + step, B.camera_length_min, B.camera_length_max
	)
