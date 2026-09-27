# Шипы (раздел 6 SPEC): статичное препятствие с отбрасыванием.
# width задаст секция при сборке; зубья рисуются примитивами.
class_name Spikes
extends Hazard

const PAL: Palette = preload("res://assets/palette.tres")

var width: float = 64.0


func _init(p_width: float = 64.0) -> void:
	width = p_width


func _ready() -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(width, 24.0)
	shape.shape = rect
	shape.position = Vector2(0, -12.0)
	add_child(shape)
	super._ready()


func _build_visual() -> void:
	# Серия треугольных зубьев шириной 16 px по всей ширине препятствия.
	var teeth := int(width / 16.0)
	for i: int in teeth:
		var x0 := -width * 0.5 + 16.0 * i
		var tooth := Prim.polygon(
			PackedVector2Array([
				Vector2(x0, 0),
				Vector2(x0 + 16.0, 0),
				Vector2(x0 + 8.0, -22.0),
			]),
			PAL.hazard
		)
		add_child(tooth)
