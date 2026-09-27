# Верёвочная лестница уступа (раздел 7.3 SPEC): поднята, пока наверху никого
# нет; опускается событием хоста, когда хотя бы один игрок оказался наверху.
# До того наверх можно попасть только «ступенькой» — прыжком с головы.
class_name RopeLadder
extends Node2D

const PAL: Palette = preload("res://assets/palette.tres")

## Шаг ступеней — прыжок 96 px, раздел 5.
const RUNG_STEP: float = 64.0

## id кооп-объекта уступа (совпадает у всех участников забега).
var ledge_id: int = -1

var _top_y: float = 0.0
var _bottom_y: float = 0.0
var _rungs: Array[StaticBody2D] = []
var _ropes: Node2D
var _dropped: bool = false


## x — позиция ноды (ставит чанк), top_y/bottom_y — границы лестницы (локальные y).
func setup(p_id: int, top_y: float, bottom_y: float) -> void:
	ledge_id = p_id
	_top_y = top_y
	_bottom_y = bottom_y


func _ready() -> void:
	# Поднята: свёрнута у верха — крюк без ступеней.
	var hook := Prim.outlined_rect(Vector2(28, 10), PAL.ladder, PAL.outline)
	hook.position = Vector2(0, _top_y)
	add_child(hook)
	_ropes = Node2D.new()
	_ropes.modulate.a = 0.0
	_ropes.add_child(_rope(-26.0))
	_ropes.add_child(_rope(26.0))
	add_child(_ropes)
	# Ступени создаём заранее скрытыми: опускание — только анимация.
	var rung_y := _bottom_y - RUNG_STEP
	while rung_y > _top_y:
		var rung := StaticBody2D.new()
		rung.collision_layer = 0  # включится при опускании
		rung.collision_mask = 0
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(64.0, 10.0)
		shape.shape = box
		rung.add_child(shape)
		rung.add_child(Prim.outlined_rect(Vector2(64.0, 10.0), PAL.ladder, PAL.outline))
		rung.position = Vector2(0, rung_y)
		rung.visible = false
		add_child(rung)
		_rungs.append(rung)
		rung_y -= RUNG_STEP
	EventBus.coop_object_opened.connect(_on_coop_opened)


func _rope(x: float) -> ColorRect:
	var rope := Prim.rect(Vector2(4.0, _bottom_y - _top_y), PAL.ladder)
	rope.position = Vector2(x, (_top_y + _bottom_y) * 0.5)
	return rope


func is_dropped() -> bool:
	return _dropped


func _on_coop_opened(opened_id: int, fallback: bool, _participants: Array[int]) -> void:
	# Запасной путь уступа — отдельная платформа, лестницу не трогает.
	if opened_id != ledge_id or fallback or _dropped:
		return
	_dropped = true
	# Верёвки натягиваются, ступени разворачиваются сверху вниз.
	var tween := create_tween()
	tween.tween_property(_ropes, "modulate:a", 1.0, 0.15)
	for i: int in _rungs.size():
		var rung: StaticBody2D = _rungs[i]
		tween.tween_callback(func() -> void:
			rung.visible = true
			rung.collision_layer = 1)
		tween.tween_interval(0.05)
