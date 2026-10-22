# Бот-пробник (временный, tools/probe_walk.gd): идёт прямо к цели,
# без прыжков и обходов — чистая проверка проходимости геометрии.
extends BotController

var target := Vector3.ZERO
var active := false


func wish_direction() -> Vector3:
	if _player == null or not active:
		return Vector3.ZERO
	var to_target := target - _player.global_position
	to_target.y = 0.0
	return to_target.normalized() if to_target.length() > 0.4 else Vector3.ZERO


func consume_jump() -> bool:
	return false


func jump_held() -> bool:
	return false


func consume_attack() -> bool:
	return false
