# Чистая вертикальная физика персонажа (раздел 5 SPEC): один шаг интеграции
# скорости, гравитация ×1.3 при падении, предел падения, высота прыжка и
# срез скорости при отпускании кнопки. Выделена из player.gd, чтобы тесты GUT
# проверяли те же формулы, что и игра (обязательный тест раздела 18: параметры
# прыжка — высота в пределах 1.3–1.5 м, «на один блок да, на два — нет»).
# Не делает: горизонтальное движение и коллизии — это CharacterBody3D.
class_name JumpMath
extends RefCounted


## Один шаг вертикальной скорости: при подъёме — обычная гравитация,
## при падении — усиленная в fall_gravity_mult раза, ниже −max_fall_speed не падаем.
static func step_vertical(velocity_y: float, delta: float, b: Balance) -> float:
	var g: float = b.gravity if velocity_y > 0.0 else b.gravity * b.fall_gravity_mult
	var next: float = velocity_y - g * delta
	return maxf(next, -b.max_fall_speed)


## Максимальная высота прыжка при полном удержании, м: v² / 2g
## (подъём идёт с обычной гравитацией — усиление действует только при падении).
static func apex_height(b: Balance) -> float:
	return apex_from(b.jump_speed, b.gravity)


## Высота подъёма с начальной скоростью v при гравитации g (м).
static func apex_from(v: float, g: float) -> float:
	return v * v / (2.0 * g)


## Скорость прыжка с усилением (прыжок с головы другого игрока).
static func boosted_jump_speed(b: Balance) -> float:
	return b.jump_speed * b.head_jump_boost


## Отпускание кнопки прыжка режет вертикальную скорость (переменная высота).
static func jump_cut(velocity_y: float, b: Balance) -> float:
	if velocity_y <= 0.0:
		return velocity_y
	return velocity_y * b.jump_cut_factor


## Пошаговая симуляция прыжка от земли до возвращения на землю.
## Возвращает {apex: float, rise_time: float, fall_speed_max: float} —
## используется тестами и отладкой (F3), игра считает то же самое в _physics_process.
static func simulate_jump(b: Balance, cut_at_fraction: float = 1.0, delta: float = 1.0 / 60.0) -> Dictionary:
	var y: float = 0.0
	var vy: float = b.jump_speed
	var apex: float = 0.0
	var rise_time: float = 0.0
	var fall_speed_max: float = 0.0
	var cut_done: bool = cut_at_fraction >= 1.0
	while true:
		# Отпускание кнопки в заданной доле подъёма: скорость срезается один раз.
		if not cut_done and apex > 0.0 and vy <= b.jump_speed * cut_at_fraction:
			vy = jump_cut(vy, b)
			cut_done = true
		vy = step_vertical(vy, delta, b)
		y += vy * delta
		apex = maxf(apex, y)
		fall_speed_max = maxf(fall_speed_max, -vy)
		if vy > 0.0:
			rise_time += delta
		if y <= 0.0 and vy < 0.0:
			break
	return {"apex": apex, "rise_time": rise_time, "fall_speed_max": fall_speed_max}
