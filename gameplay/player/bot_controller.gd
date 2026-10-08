# Бот для нагрузочных прогонов (--bot, раздел 18 SPEC): бродит по острову
# между точками интереса (зоны и камни духа — задаёт сцена мира в
# set_targets), по пути иногда прыгает, бьёт мобов в радиусе, у точки
# делает паузу. Застрял (нет прогресса) — прыжок, после нескольких попыток —
# новая цель; упал в расщелину — висит и переносится таймером «Висит».
# Заменяет ввод игрока (wish_direction/jump/attack), больше ничего
# не решает. Параметры — группа «Боты» в balance.tres.
class_name BotController
extends Node

const B: Balance = preload("res://gameplay/balance.tres")

var _player: Player = null
var _targets: Array[Vector3] = []
var _rng := RandomNumberGenerator.new()  # боты не обязаны быть детерминированы
var _target := Vector3.ZERO
var _has_target := false
var _pause_left: float = 0.0
var _stuck_left: float = 0.0
var _stuck_jumps: int = 0
var _jump_requested := false
var _attack_requested := false
var _jump_hold_left := 0.0


func setup(player: Player) -> void:
	_player = player


## Точки интереса для прогулки (сцена мира: зоны появления, камни духа).
func set_targets(points: Array) -> void:
	_targets.assign(points)


func _physics_process(delta: float) -> void:
	if _player == null:
		return
	_jump_hold_left = maxf(0.0, _jump_hold_left - delta)
	if _pause_left > 0.0:
		_pause_left -= delta
		return
	if not _has_target:
		if _targets.is_empty():
			return
		_pick_target()
	_jump_or_attack_tick(delta)
	_check_stuck(delta)
	_turn_camera(delta)


func _pick_target() -> void:
	# Случайная точка, не совпадающая с предыдущей (кроме единственной).
	if _targets.size() == 1:
		_target = _targets[0]
	else:
		var pick := _target
		while pick == _target:
			pick = _targets[_rng.randi_range(0, _targets.size() - 1)]
		_target = pick
	_has_target = true
	_stuck_jumps = 0
	Log.info("Бот %d идёт к точке (%.0f, %.0f)" % [Net.local_peer_id, _target.x, _target.z], "Bot")


func _jump_or_attack_tick(delta: float) -> void:
	# Моб рядом — идём на него и бьём (зону удара поворачивает модель).
	var mob := _nearest_mob()
	if mob != null:
		var to_mob: Vector3 = mob.global_position - _player.global_position
		if to_mob.length() <= B.bot_attack_radius * 0.6:
			_attack_requested = true
	# Иногда прыгнуть на ходу (раздел 17: «иногда прыгают»).
	if _rng.randf() < B.bot_jump_chance_per_sec * delta:
		_request_jump()


func _check_stuck(delta: float) -> void:
	# Прогресса нет (скорость почти ноль при цели) — прыжок, после трёх
	# попыток новая цель (дерево, стена расщелины, вода).
	var horizontal := Vector2(_player.velocity.x, _player.velocity.z).length()
	if horizontal < 0.5:
		_stuck_left += delta
		if _stuck_left >= B.bot_stuck_time:
			_stuck_left = 0.0
			_stuck_jumps += 1
			if _stuck_jumps > 3:
				_has_target = false
			else:
				_request_jump()
	else:
		_stuck_left = 0.0
		_stuck_jumps = maxi(0, _stuck_jumps - 1)


func _turn_camera(delta: float) -> void:
	# Косметика: камера смотрит по курсу (движение бота от камеры не зависит).
	var look := _player.camera.forward_flat()
	var want := (_target - _player.global_position)
	want.y = 0.0
	if want.length() > 0.5:
		_player.camera.rotation.y = lerp_angle(
			_player.camera.rotation.y, atan2(-want.x, -want.z),
			B.bot_turn_speed * delta
		)


func _nearest_mob() -> Mob:
	var best: Mob = null
	var best_distance: float = B.bot_attack_radius
	for node: Node in get_tree().get_nodes_in_group(Mob.GROUP):
		var mob := node as Mob
		if mob == null or not mob.is_alive():
			continue
		var distance: float = mob.global_position.distance_to(_player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = mob
	return best


func _request_jump() -> void:
	_jump_requested = true
	_jump_hold_left = B.bot_jump_hold


## Куда идти (мировые координаты, в плоскости земли); у цели — стоять.
func wish_direction() -> Vector3:
	if _pause_left > 0.0 or not _has_target:
		return Vector3.ZERO
	var mob := _nearest_mob()
	var point := _target
	if mob != null and mob.is_alive():
		point = mob.global_position
	var to_point := point - _player.global_position
	to_point.y = 0.0
	if to_point.length() < B.bot_arrive_radius:
		if point == _target:
			_has_target = false
			_pause_left = B.bot_poi_pause
		return Vector3.ZERO
	return to_point.normalized()


## Прыжок запрошен (одноразово, как just_pressed).
func consume_jump() -> bool:
	var value := _jump_requested
	_jump_requested = false
	return value


## Держит ли бот кнопку прыжка (полная высота прыжка).
func jump_held() -> bool:
	return _jump_hold_left > 0.0


## Атака запрошена (одноразово; частоту ограничивает перезарядка удара).
func consume_attack() -> bool:
	var value := _attack_requested
	_attack_requested = false
	return value
