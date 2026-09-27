# Чекпоинт секции (раздел 5): маркер в начале секции; пересечение запоминает
# точку возврата. Событие уходит через EventBus — кто хранит чекпоинт,
# решает сцена забега (только вперёд, чтобы не откатываться).
class_name CheckpointArea
extends Area2D

const PAL: Palette = preload("res://assets/palette.tres")

var index: int = 0

var _activated: bool = false


func setup(p_index: int) -> void:
	index = p_index


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(48, 160)
	shape.shape = box
	shape.position = Vector2(0, -60)
	add_child(shape)
	# Флажок чекпоинта.
	var pole := Prim.rect(Vector2(4, 64), PAL.outline)
	pole.position = Vector2(0, -32)
	add_child(pole)
	var flag := Prim.polygon(
		PackedVector2Array([Vector2(2, -60), Vector2(30, -52), Vector2(2, -44)]),
		PAL.checkpoint
	)
	add_child(flag)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if _activated or not (body is Player):
		return
	_activated = true
	EventBus.checkpoint_reached.emit(index, global_position)
