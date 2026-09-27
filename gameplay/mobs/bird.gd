# Птица (раздел 6 SPEC): летает по синусоиде вдоль участка 400–800 px,
# 1 удар до смерти. Позиция — чистая функция времени забега.
class_name BirdMob
extends Mob

const PAL: Palette = preload("res://assets/palette.tres")

var _visual: Node2D


func _init() -> void:
	super(Vector2(26, 18))


## Смещение от точки спавна: патруль по синусу вдоль участка span,
## плюс вертикальная волна — «синусоида вдоль участка» из раздела 6.
func compute_offset(t: float) -> Vector2:
	return trajectory(params, t)


static func trajectory(params: Dictionary, t: float) -> Vector2:
	var span: float = params.get("span", 400.0)
	var period: float = params.get("period", 6.0)
	var dir: float = signf(params.get("dir", 1.0))
	var phase: float = params.get("phase", 0.0)
	var x: float = span * 0.5 * sin(TAU * t / period + phase) * dir
	var wave_amp: float = params.get("wave_amp", 28.0)
	var wave_period: float = params.get("wave_period", 2.4)
	var y: float = wave_amp * sin(TAU * t / wave_period + phase)
	return Vector2(x, y)


func _build_visual() -> void:
	_visual = Prim.outlined_rect(Vector2(26, 16), PAL.bird, PAL.outline)
	_visual.add_child(Prim.rect(Vector2(10, 6), PAL.outline))  # клюв
	var wing := Prim.rect(Vector2(14, 6), Color(1, 1, 1, 0.75))
	wing.position = Vector2(0, -12)
	_visual.add_child(wing)
	add_child(_visual)


func _update_position(t: float) -> void:
	super(t)
	# Разворот по горизонтали: смотрит по направлению движения.
	var dx: float = cos(TAU * t / params.get("period", 6.0) + params.get("phase", 0.0))
	_visual.scale.x = 1.0 if dx * signf(params.get("dir", 1.0)) >= 0.0 else -1.0
