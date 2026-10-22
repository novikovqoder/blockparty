# Временный пробник (не коммитить): старт в комнате крыла, цель — проём.
# Печать x;y;z;on_floor;velocity — почему бот замирает у северного косяка.
extends GutTest

const ISLAND: PackedScene = preload("res://gameplay/world/island.tscn")
const PLAYER: PackedScene = preload("res://gameplay/player/player.tscn")

const FAST_TICKS: int = 240


class Walker extends BotController:
	var target := Vector3.ZERO
	var active := false
	var _halt_left := 0.0
	var _side_left := 0.0
	var _side_sign := 1.0
	var _side_switched := 0


	func _physics_process(delta: float) -> void:
		if _player == null or not active:
			return
		var horizontal := Vector2(_player.velocity.x, _player.velocity.z).length()
		if _side_left > 0.0:
			_side_left -= delta
		elif horizontal < 0.5:
			_halt_left += delta
			if _halt_left >= 1.2:
				_halt_left = 0.0
				_side_left = 1.0
				_side_switched += 1
				if _side_switched % 2 == 0:
					_side_sign = -_side_sign
		else:
			_halt_left = 0.0


	func wish_direction() -> Vector3:
		if _player == null or not active:
			return Vector3.ZERO
		var to_target := target - _player.global_position
		to_target.y = 0.0
		if to_target.length() < 0.5:
			return Vector3.ZERO
		var dir := to_target.normalized()
		if _side_left > 0.0:
			var side := Vector3(-dir.z, 0.0, dir.x) * _side_sign
			dir = (dir + side * 1.4).normalized()
		return dir


	func consume_jump() -> bool:
		return false


	func jump_held() -> bool:
		return false


	func consume_attack() -> bool:
		return false


func before_all() -> void:
	Engine.physics_ticks_per_second = FAST_TICKS


func after_all() -> void:
	Engine.physics_ticks_per_second = 60


func test_probe_exit() -> void:
	var world := ISLAND.instantiate()
	add_child_autofree(world)
	var house: Node3D = null
	for child in world.get_children():
		if child.name.begins_with("Cabin"):
			house = child
			break
	var walker := Walker.new()
	add_child_autofree(walker)
	var player := PLAYER.instantiate()
	world.add_child(player)
	player.global_position = house.global_transform * Vector3(2.7, 0.36, -5.2)
	walker.setup(player)
	player._bot = walker
	for i: int in 60:
		await get_tree().physics_frame
	walker.target = house.global_transform * Vector3(1.1, 0.62, -5.2)
	walker.active = true
	var target := walker.target
	for i: int in int(15.0 * FAST_TICKS):
		await get_tree().physics_frame
		if i % 60 == 0:
			var p: Vector3 = player.global_position
			var hl: Vector3 = house.global_transform.affine_inverse() * p
			print("PROBE t=%.2f pos=(%.2f, %.2f, %.2f) local=(%.2f, %.2f) floor=%s wall=%s sit=%s hang=%s vel=%s" % [
				i / float(FAST_TICKS), p.x, p.y, p.z, hl.x, hl.z,
				player.is_on_floor(), player.is_on_wall(),
				player.get("_sitting"), player.get("_hanging"), player.velocity])
			print("  wish=%s target=%s dist=%.2f side_left=%.2f" % [
				walker.wish_direction(), walker.target,
				(walker.target - player.global_position).length(),
				walker.get("_side_left")])
		var flat := Vector2(p2(player).x - target.x, p2(player).z - target.z)
		if flat.length() < 0.55 and player.is_on_floor():
			print("PROBE ДОВЁЛ")
			break
	walker.active = false
	walker.setup(null)
	player.queue_free()
	assert_true(true)


func p2(player: Node3D) -> Vector3:
	return player.global_position
