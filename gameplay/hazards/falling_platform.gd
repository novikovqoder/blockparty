# Падающая платформа (раздел 6 SPEC): падает через falling_platform_delay
# после того, как на неё встал игрок, и восстанавливается через
# falling_platform_restore. Момент падения рассылает хост (rpc_platform_state),
# поэтому у всех она падает одновременно; хост считает стоящих по позициям.
class_name FallingPlatform
extends StaticBody2D

const PAL: Palette = preload("res://assets/palette.tres")

## id платформы (совпадает у всех участников забега).
var platform_id: int = -1

var _origin_y: float = 0.0
var _fallen: bool = false


func setup(p_id: int, size: Vector2) -> void:
	platform_id = p_id
	collision_layer = 1
	collision_mask = 0
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = size
	shape.shape = box
	add_child(shape)
	add_child(Prim.outlined_rect(size, PAL.platform, PAL.outline))


func _ready() -> void:
	_origin_y = position.y
	EventBus.platform_state_changed.connect(_on_platform_state)


## Зона поверхности для хоста (кто «стоит на платформе», раздел 6).
func zone() -> Rect2:
	var size: Vector2 = ($CollisionShape2D.shape as RectangleShape2D).size
	var center: Vector2 = global_position + Vector2(0.0, -size.y * 0.5)
	return Rect2(center.x - size.x * 0.5 - 8.0, center.y - 16.0, size.x + 16.0, 24.0)


func is_fallen() -> bool:
	return _fallen


func _on_platform_state(changed_id: int, fallen: bool) -> void:
	if changed_id != platform_id or fallen == _fallen:
		return
	_fallen = fallen
	if fallen:
		# Дрожь, падение вниз и растворение; коллизия сразу off.
		set_deferred("collision_layer", 0)
		var shake := create_tween()
		shake.tween_property(self, "position:x", position.x + 5.0, 0.05)
		shake.tween_property(self, "position:x", position.x - 5.0, 0.05)
		shake.tween_property(self, "position:x", position.x, 0.05)
		var fall := create_tween()
		fall.tween_interval(0.15)
		fall.set_parallel(true)
		fall.tween_property(self, "position:y", _origin_y + 480.0, 0.5).set_ease(Tween.EASE_IN)
		fall.tween_property(self, "modulate:a", 0.0, 0.5)
	else:
		# Возврат на место (раздел 6: восстанавливается через 5 с).
		position.y = _origin_y
		modulate = Color.TRANSPARENT
		var tween := create_tween()
		tween.tween_property(self, "modulate:a", 1.0, 0.3)
		set_deferred("collision_layer", 1)
