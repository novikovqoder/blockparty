# Стрелки-указатели в мире (раздел 7.5, 7.1 SPEC): «Сюда!» — маркер-стрелка
# в точке, куда смотрит отправитель эмоции (3 с); «Помогите!» — указатель на
# висящего игрока. Создаёт сцена забега по событиям эмоций; исчезает сама.
class_name WorldMarker
extends Node2D

const PAL: Palette = preload("res://assets/palette.tres")

enum Kind { HERE, HELP }

var _ttl: float = 3.0
var _visual: Node2D


func setup(kind: int, ttl: float) -> void:
	_ttl = ttl
	_visual = _build(kind)
	add_child(_visual)
	var pulse := create_tween().set_loops()
	pulse.tween_property(_visual, "scale", Vector2(1.18, 1.18), 0.3)
	pulse.tween_property(_visual, "scale", Vector2.ONE, 0.3)


func _process(delta: float) -> void:
	_ttl -= delta
	if _ttl <= 0.0:
		queue_free()


func _build(kind: int) -> Node2D:
	if kind == Kind.HERE:
		# Стрелка, указывающая вниз на точку.
		var arrow := Prim.polygon(
			PackedVector2Array([Vector2(-16, -14), Vector2(16, -14), Vector2(0, 14)]),
			PAL.marker
		)
		var ring := Prim.outlined_rect(Vector2(10, 10), Color(1, 1, 1, 0), PAL.marker, 2.0)
		ring.position = Vector2(0, -26)
		arrow.add_child(ring)
		return arrow
	# «Помогите!»: восклицательный знак в ромбе над висящим.
	var diamond := Prim.polygon(
		PackedVector2Array([Vector2(0, -22), Vector2(18, 0), Vector2(0, 22), Vector2(-18, 0)]),
		PAL.marker
	)
	var bar := Prim.rect(Vector2(6, 18), PAL.outline)
	bar.position = Vector2(0, -6)
	var dot := Prim.rect(Vector2(6, 6), PAL.outline)
	dot.position = Vector2(0, 10)
	diamond.add_child(bar)
	diamond.add_child(dot)
	return diamond
