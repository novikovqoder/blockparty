# Зверёк (раздел 6 SPEC): бегает по земле туда-обратно в пределах платформы,
# разворачивается у края. 1 удар до смерти. Чистая функция времени.
class_name CritterMob
extends Mob

const PAL: Palette = preload("res://assets/palette.tres")

var _visual: Node2D


func _init() -> void:
	super(Vector2(22, 16))


## Смещение от точки спавна: треугольная волна — равномерный бег туда-обратно.
func compute_offset(t: float) -> Vector2:
	return trajectory(params, t)


static func trajectory(params: Dictionary, t: float) -> Vector2:
	var span: float = params.get("span", 256.0)
	var period: float = params.get("period", 4.0)
	return Vector2(span * 0.5 * Mob.triangle_wave(t * 2.0 / period), 0.0)


func _build_visual() -> void:
	_visual = Prim.outlined_rect(Vector2(22, 14), PAL.critter, PAL.outline)
	var ear := Prim.rect(Vector2(4, 6), PAL.critter)
	ear.position = Vector2(-6, -10)
	_visual.add_child(ear)
	var eye := Prim.rect(Vector2(4, 4), PAL.outline)
	eye.position = Vector2(7, -3)
	_visual.add_child(eye)
	add_child(_visual)


func _update_position(t: float) -> void:
	super(t)
	# Направление бега: знак наклона треугольной волны.
	var phase := fmod(t * 2.0 / params.get("period", 4.0), 2.0)
	if phase < 0.0:
		phase += 2.0
	_visual.scale.x = 1.0 if phase < 1.0 else -1.0
