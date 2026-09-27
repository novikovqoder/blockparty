# Хелперы плейсхолдер-визуала из примитивов (раздел 14 SPEC): центр всего
# в точке (0,0) родителя. Внешних ассетов нет — всё рисуется ColorRect/Polygon2D.
class_name Prim
extends RefCounted


## Прямоугольник заданного размера с центром в начале координат родителя.
static func rect(size: Vector2, color: Color) -> ColorRect:
	var node := ColorRect.new()
	node.color = color
	node.size = size
	node.pivot_offset = size * 0.5
	node.position = -size * 0.5
	return node


## Прямоугольник с толстым тёмным контуром (стиль MVP) как один узел-группа.
static func outlined_rect(size: Vector2, color: Color, outline: Color, thickness: float = 2.0) -> Node2D:
	var root := Node2D.new()
	var back := rect(size + Vector2(thickness, thickness) * 2.0, outline)
	root.add_child(back)
	root.add_child(rect(size, color))
	return root


## Многоугольник по точкам относительно центра.
static func polygon(points: PackedVector2Array, color: Color) -> Polygon2D:
	var node := Polygon2D.new()
	node.polygon = points
	node.color = color
	return node
