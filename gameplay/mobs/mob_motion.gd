# Траектории мобов (раздел 8 SPEC) — чистые функции от часов мира
# (Session.world_time) и параметров появления из IslandGen: движение
# детерминировано (правило проекта: только фиксированные seed и формулы,
# никаких randf в рантайме) и одинаково у всех участников мира — в сети
# мобов не нужно синхронизировать, достаточно одинаковых часов (П3).
# Тесты GUT проверяют замкнутость и непрерывность траекторий.
class_name MobMotion
extends RefCounted


## Птица: круг против/по часовой стрелке над центром (center — точка над
## землёй, height — дополнительный подъём, period — полный круг, с).
static func bird_position(params: Dictionary, world_time: float) -> Vector3:
	var angle: float = _bird_angle(params, world_time)
	# x = sin/z = cos (а не cos/sin), чтобы heading(yaw) = (sin, 0, cos)
	# совпадал с радиальным направлением при yaw = angle — тогда касательная
	# к кругу задаётся формулой bird_yaw (angle ± π/2) без рассинхрона систем
	# координат (проверяется тестом «курс ⊥ радиусу»).
	return params["center"] + Vector3(
		sin(angle) * float(params["radius"]),
		float(params["height"]),
		cos(angle) * float(params["radius"]),
	)


## Курс птицы (куда смотрит модель): касательная к кругу.
static func bird_yaw(params: Dictionary, world_time: float) -> float:
	return _bird_angle(params, world_time) + PI * 0.5 * float(params["direction"])


static func _bird_angle(params: Dictionary, world_time: float) -> float:
	return float(params["phase"]) \
		+ TAU * float(params["direction"]) * world_time / float(params["period"])


## Зверёк: замкнутый маршрут по точкам с постоянной скоростью; позиции точек
## лежат на земле (IslandGen), движение по сегментам с интерполяцией высоты.
static func critter_position(params: Dictionary, world_time: float) -> Vector3:
	var points: Array = params["points"]
	if points.size() < 2:
		return points[0] if points.size() == 1 else Vector3.ZERO
	var total: float = 0.0
	for i: int in points.size():
		total += _segment_length(points, i)
	var traveled: float = fposmod(world_time * float(params["speed"]), total)
	for i: int in points.size():
		var length: float = _segment_length(points, i)
		if traveled <= length:
			var t: float = traveled / length if length > 0.0 else 0.0
			var a: Vector3 = points[i]
			var b: Vector3 = points[(i + 1) % points.size()]
			return a.lerp(b, t)
		traveled -= length
	return points[0]


## Курс зверька: yaw текущего сегмента маршрута.
static func critter_yaw(params: Dictionary, world_time: float) -> float:
	var points: Array = params["points"]
	if points.size() < 2:
		return 0.0
	var total: float = 0.0
	for i: int in points.size():
		total += _segment_length(points, i)
	var traveled: float = fposmod(world_time * float(params["speed"]), total)
	for i: int in points.size():
		var length: float = _segment_length(points, i)
		if traveled <= length:
			var a: Vector3 = points[i]
			var b: Vector3 = points[(i + 1) % points.size()]
			return atan2(b.x - a.x, b.z - a.z)
		traveled -= length
	return 0.0


static func _segment_length(points: Array, i: int) -> float:
	var a: Vector3 = points[i]
	var b: Vector3 = points[(i + 1) % points.size()]
	return a.distance_to(b)


## Золотой светлячок: дрейф по Лиссажу вокруг центра (парит в чаще),
## вертикаль — отдельная частота, чтобы не крутиться по идеальному кругу.
static func firefly_position(params: Dictionary, world_time: float) -> Vector3:
	var drift: float = float(params["drift"])
	var period: float = float(params["period"])
	var phase: float = float(params["phase"])
	var t: float = TAU * world_time / period + phase
	return params["center"] + Vector3(
		sin(t * 0.7) * drift,
		sin(t * 1.1) * 0.4,
		cos(t * 0.5) * drift,
	)


## Яркость вспышки светлячка [0, 1] — мягкие пульсации.
static func firefly_glow(params: Dictionary, world_time: float) -> float:
	var t: float = TAU * world_time / float(params["period"]) + float(params["phase"])
	return 0.55 + 0.45 * sin(t * 2.0)
