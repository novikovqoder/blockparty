# Движущаяся платформа (раздел 6 SPEC): движение по пути детерминировано
# от run_time и параметров спавна, без сетевой синхронизации. AnimatableBody2D
# c sync_to_physics переносит стоящего игрока.
class_name MovingPlatform
extends AnimatableBody2D

const PAL: Palette = preload("res://assets/palette.tres")

var params: Dictionary = {}

var _origin: Vector2 = Vector2.ZERO


## Размер платформы и параметры траектории: axis, amp, period, phase.
func setup(size: Vector2, p_params: Dictionary) -> void:
	params = p_params
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = size
	shape.shape = box
	add_child(shape)
	add_child(Prim.outlined_rect(size, PAL.platform, PAL.outline))


func _ready() -> void:
	# Локальная точка пути: чанк уже стоит на своём offset_x, глобальная
	# позиция здесь дала бы двойное смещение.
	_origin = position


func _physics_process(_delta: float) -> void:
	position = _origin + trajectory(params, Session.run_time)


## Чистая функция смещения — проверяется тестом на детерминизм.
static func trajectory(params: Dictionary, t: float) -> Vector2:
	var axis: Vector2 = params.get("axis", Vector2.RIGHT)
	var amp: float = params.get("amp", 96.0)
	var period: float = params.get("period", 4.0)
	var phase: float = params.get("phase", 0.0)
	return axis.normalized() * amp * sin(TAU * t / period + phase)
