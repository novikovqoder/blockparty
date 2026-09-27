# Кактус (раздел 6 SPEC): статичное препятствие с отбрасыванием, без урона.
class_name Cactus
extends Hazard

const PAL: Palette = preload("res://assets/palette.tres")


func _ready() -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(24, 40)
	shape.shape = rect
	shape.position = Vector2(0, -20)
	add_child(shape)
	super._ready()


func _build_visual() -> void:
	var body := Prim.outlined_rect(Vector2(24, 40), PAL.cactus, PAL.outline)
	body.position = Vector2(0, -20)
	add_child(body)
	var arm := Prim.outlined_rect(Vector2(12, 18), PAL.cactus, PAL.outline)
	arm.position = Vector2(-16, -18)
	add_child(arm)
