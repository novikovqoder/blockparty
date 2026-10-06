# Полоска характеристики (экран выбора персонажа, раздел 15): 5 делений
# с зазором; при смене персонажа плавно заполняется за 0.3 с.
class_name StatBar
extends Control

const SEGMENTS: int = 5
const GAP: float = 4.0
## Время плавного заполнения, с.
const FILL_TIME: float = 0.3
const BACK_COLOR: Color = Color(0.24, 0.24, 0.28)

## Цвет заливки — цвет характеристики (совпадает со StatIcon).
@export var fill_color: Color = Color(0.85, 0.45, 0.35)

## Текущее заполнение (дробное — виден ход анимации) и цель 0…5.
var _value: float = 0.0
var _target: float = 0.0


## Показать значение мгновенно (первое заполнение экрана).
func set_value(value: int) -> void:
	_value = value
	_target = value
	queue_redraw()


## Плавно довести полоску до значения (0.3 с).
func animate_to(value: int) -> void:
	_target = value


func value() -> float:
	return _value


func _process(delta: float) -> void:
	if is_equal_approx(_value, _target):
		return
	_value = move_toward(_value, _target, SEGMENTS / FILL_TIME * delta)
	queue_redraw()


func _draw() -> void:
	var width: float = (size.x - GAP * (SEGMENTS - 1)) / SEGMENTS
	for i: int in SEGMENTS:
		var rect := Rect2(Vector2(i * (width + GAP), 0.0),
			Vector2(width, size.y))
		draw_rect(rect, BACK_COLOR)
		# Сегмент i заполнен целиком, если _value >= i+1; частично — доля.
		var fill: float = clampf(_value - i, 0.0, 1.0)
		if fill <= 0.0:
			continue
		rect.size.x *= fill
		draw_rect(rect, fill_color)
