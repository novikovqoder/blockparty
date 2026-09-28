# Нажимная плита (раздел 7.2 SPEC): перед кооп-воротами; хост считает
# нажатость по позициям игроков (снапшоты), поэтому плите не нужен id —
# локально она только проседает, когда на ней стоит свой персонаж (отклик).
class_name PressurePlate
extends Area2D

const PAL: Palette = preload("res://assets/palette.tres")

const WIDTH: float = 96.0
const THICKNESS: float = 12.0

var _top_y: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	add_to_group("pressure_plate")  # бот находит свою плиту по группе
	_top_y = position.y
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(WIDTH, THICKNESS)
	shape.shape = box
	add_child(shape)
	add_child(_visual())
	body_entered.connect(_on_body)
	body_exited.connect(_on_body_exit)


## Верх плиты в мировых координатах (зону для хоста строит LevelBuilder).
func zone() -> Rect2:
	var center: Vector2 = global_position + Vector2(0, -8.0)
	return Rect2(center - Vector2(WIDTH * 0.5, 24.0), Vector2(WIDTH, 48.0))


func _visual() -> Node2D:
	var node := Prim.outlined_rect(Vector2(WIDTH, THICKNESS), PAL.plate, PAL.outline)
	node.position = Vector2(0, -THICKNESS * 0.5)
	return node


## Локальный отклик: своя плита проседает, когда на ней кто-то стоит.
func _on_body(_body: Node2D) -> void:
	var tween := create_tween()
	tween.tween_property(self, "position:y", _top_y + 4.0, 0.08)


func _on_body_exit(_body: Node2D) -> void:
	var tween := create_tween()
	tween.tween_property(self, "position:y", _top_y, 0.08)
