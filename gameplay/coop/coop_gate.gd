# Кооп-ворота (раздел 7.2 SPEC): стена, преграждающая секцию; открывается
# событием хоста (rpc_coop_open) — когда на плитах стоит need разных игроков
# или сработал запасной таймер 45 с. После открытия — навсегда. Монеты
# участникам начисляет Net, здесь только геометрия и анимация.
class_name CoopGate
extends StaticBody2D

const PAL: Palette = preload("res://assets/palette.tres")

## id кооп-объекта из LevelPlan (совпадает у всех участников забега).
var object_id: int = -1

var _opened: bool = false
var _door: Node2D
var _base_y: float = 0.0


func setup(p_id: int, width: float, height: float) -> void:
	object_id = p_id
	collision_layer = 1
	collision_mask = 0
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(width, height)
	shape.shape = box
	shape.position = Vector2(0, -height * 0.5)
	add_child(shape)
	_door = Prim.outlined_rect(Vector2(width, height), PAL.gate, PAL.outline)
	_door.position = Vector2(0, -height * 0.5)
	_door.add_child(_stripes(width, height))
	add_child(_door)
	add_to_group("coop_gate")


func _ready() -> void:
	_base_y = _door.position.y
	EventBus.coop_object_opened.connect(_on_coop_opened)


## Ворота открыты (для бота: можно не ждать у плит).
func is_open() -> bool:
	return _opened


func _on_coop_opened(opened_id: int, _fallback: bool, _participants: Array[int]) -> void:
	if opened_id != object_id or _opened:
		return
	_opened = true
	# Вспышка и дверь уезжает вверх (раздел 14: вспышка при открытии ворот).
	set_deferred("collision_layer", 0)
	var flash := create_tween()
	flash.tween_property(_door, "modulate", Color(2.2, 2.2, 2.6), 0.12)
	flash.tween_property(_door, "modulate", Color.WHITE, 0.25)
	var lift := create_tween()
	lift.tween_property(_door, "position:y", _base_y - 640.0, 0.7).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)


func _stripes(width: float, height: float) -> Node2D:
	# «Запрещающие» полосы — ворота читаются как преграда.
	var root := Node2D.new()
	for i: int in int(height / 96.0):
		var stripe := Prim.rect(Vector2(width * 0.6, 18.0), Color(1, 1, 1, 0.25))
		stripe.position = Vector2(0, -height * 0.5 + 48.0 + 96.0 * i)
		stripe.rotation = 0.35
		root.add_child(stripe)
	return root
