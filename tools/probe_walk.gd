# Пробник (временный): прямой ход игрока к двери сруба — где затык.
# В отличие от GUT-теста, никакой обходной логики: чистое направление
# на цель. Запуск: godot --headless -s tools/probe_walk.gd
extends SceneTree

const ISLAND: PackedScene = preload("res://gameplay/world/island.tscn")
const PLAYER: PackedScene = preload("res://gameplay/player/player.tscn")
const STRAIGHT_BOT: GDScript = preload("res://tools/probe_straight_bot.gd")


func _init() -> void:
	Engine.physics_ticks_per_second = 480
	Engine.max_physics_steps_per_frame = 10


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var island := ISLAND.instantiate()
	get_root().add_child(island)
	await physics_frame
	await physics_frame
	var house: Node3D = null
	for child in island.get_children():
		if child.name.begins_with("Cabin"):
			house = child
			break
	print("дом: %s pos=%s" % [house.name, house.global_position])
	# Без аннотации типа: у пробника свои поля target/active, которых
	# нет в базовом BotController — зовём по утиной типизации.
	var bot := STRAIGHT_BOT.new()
	get_root().add_child(bot)
	var player := PLAYER.instantiate()
	island.add_child(player)
	var start: Vector3 = house.global_transform * Vector3(-4.5, 0.0, -5.2)
	player.global_position = start + Vector3(0.0, 0.2, 0.0)
	bot.setup(player)
	player._bot = bot
	for i: int in 120:
		await physics_frame
	var legs: Array[Vector3] = [
		Vector3(-0.85, 0.0, -5.2),
		Vector3(0.3, 0.0, -5.2),
		Vector3(1.1, 0.0, -5.2),
		Vector3(2.7, 0.0, -5.2),
	]
	for leg: Vector3 in legs:
		var target: Vector3 = house.global_transform * leg
		bot.target = target
		bot.active = true
		var local_name := "(%.1f, %.1f)" % [target.x, target.z]
		var trace := ""
		var arrived := false
		for i: int in int(12.0 * 480.0):
			await physics_frame
			if i % 240 == 0:
				var lp: Vector3 = player.global_position
				trace += " [%.1f;%.1f;%.2f]" % [lp.x, lp.z, lp.y]
				var flat := Vector2(lp.x - target.x, lp.z - target.z)
				if flat.length() < 0.5 and player.is_on_floor():
					arrived = true
					break
		print("нога %s: %s%s" % [leg, trace, " ДОВЁЛ" if arrived else " НЕ дошёл"])
	bot.active = false
	quit()
