# Значок характеристики для экрана выбора персонажа (раздел 15): простая
# фигура цветом строки — ромб-гиря (сила), молния (скорость), стрелка
# вверх (прыжок). Рисуется сам, без текстур и шрифтов.
class_name StatIcon
extends Control

enum Kind { STRENGTH, SPEED, JUMP }

## Цвет совпадает с заливкой полоски той же характеристики (StatBar).
@export var kind: Kind = Kind.STRENGTH

const KIND_COLORS: Array[Color] = [
	Color(0.85, 0.45, 0.35),
	Color(0.95, 0.78, 0.30),
	Color(0.42, 0.78, 0.72),
]


func _draw() -> void:
	var color: Color = KIND_COLORS[kind]
	match kind:
		Kind.STRENGTH:
			_draw_poly(color, [Vector2(0.5, 0.05), Vector2(0.95, 0.5),
				Vector2(0.5, 0.95), Vector2(0.05, 0.5)])
		Kind.SPEED:
			_draw_poly(color, [Vector2(0.62, 0.0), Vector2(0.18, 0.55),
				Vector2(0.45, 0.55), Vector2(0.33, 1.0),
				Vector2(0.82, 0.42), Vector2(0.52, 0.42)])
		Kind.JUMP:
			_draw_poly(color, [Vector2(0.5, 0.0), Vector2(0.14, 0.45),
				Vector2(0.86, 0.45)])
			draw_rect(Rect2(Vector2(0.4, 0.45) * size,
				Vector2(0.2, 0.5) * size), color)


func _draw_poly(color: Color, points: Array) -> void:
	var scaled := PackedVector2Array()
	for point: Vector2 in points:
		scaled.append(point * size)
	var colors: PackedColorArray = PackedColorArray()
	colors.append(color)
	draw_polygon(scaled, colors)
