# Чистая логика состояния «Висит» (раздел 9.1 SPEC): таймер висения у края
# и выбор ближайшей точки HangPoint. Выделена из нод, чтобы тесты GUT
# проверяли её напрямую (обязательный тест раздела 18), а HangArea и хост
# (в сети — этап П3) использовали один и тот же код.
# Не делает: вытягивание другим игроком (П5), emocию «Помогите!» (П5).
class_name HangLogic
extends RefCounted

var time_left: float = 0.0
var hanging: bool = false


## Начать висение с заданным запасом времени, с.
func start(time: float) -> void:
	hanging = true
	time_left = time


## Прервать висение (вытянули — П5; перенос — expire).
func stop() -> void:
	hanging = false
	time_left = 0.0


## Тик таймера; возвращает true, когда время вышло (перенос к Камню духа).
func tick(delta: float) -> bool:
	if not hanging:
		return false
	time_left = maxf(time_left - delta, 0.0)
	if time_left <= 0.0:
		hanging = false
		return true
	return false


## Ближайшая точка цепляния к позиции упавшего (видна как светящаяся точка).
static func nearest_point(points: Array[Vector3], position: Vector3) -> Vector3:
	var best := Vector3.ZERO
	var best_dist: float = INF
	for point: Vector3 in points:
		var dist: float = point.distance_squared_to(position)
		if dist < best_dist:
			best_dist = dist
			best = point
	return best
