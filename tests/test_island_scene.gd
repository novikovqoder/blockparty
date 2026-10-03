# Интеграционные тесты сцены острова (этап П2): island.tscn соответствует
# данным IslandGen (тот же GridMap), в сцене 60 монет и все мобы, персонаж
# стоит на земле во всех зонах (--dev-spawn), монета подбирается касанием,
# удар игрока убивает моба. Сцена коммитится — по сети не передаётся.
extends GutTest

const ISLAND: PackedScene = preload("res://gameplay/world/island.tscn")
const PLAYER: PackedScene = preload("res://gameplay/player/player.tscn")
const B: Balance = preload("res://gameplay/balance.tres")

## Кэш данных генератора между тестами (generate() дорогой, ~10 с).
static var _gen_cache: Dictionary = {}


func _island_data() -> Dictionary:
	if _gen_cache.is_empty():
		_gen_cache = IslandGen.generate()
	return _gen_cache


func test_gridmap_matches_generator() -> void:
	var island := ISLAND.instantiate() as Island
	add_child_autofree(island)
	var grid := island.get_node("GridMap") as GridMap
	var cells: Array = grid.get_used_cells()
	assert_eq(cells.size(), IslandGen.cells(_island_data()).size(), "клеток как в генераторе")
	assert_eq(cells.size(), 80682, "остров не перегенерирован молча")


func test_scene_contents() -> void:
	var island := ISLAND.instantiate() as Island
	add_child_autofree(island)
	var coins := 0
	var coin_ids: Dictionary = {}
	var birds := 0
	var critters := 0
	var fireflies := 0
	var water := 0
	var markers := 0
	for child: Node in island.get_children():
		if child is CoinPickup:
			coins += 1
			coin_ids[(child as CoinPickup).spawn_id] = true
		elif child is Bird:
			birds += 1
		elif child is Critter:
			critters += 1
		elif child is GoldenFirefly:
			fireflies += 1
		elif child is WaterArea:
			water += 1
		elif child is HangArea:
			markers = (child as HangArea).point_positions().size()
	assert_eq(coins, B.static_coins, "ровно 60 статичных монет")
	assert_eq(coin_ids.size(), coins, "spawn_id монет уникальны")
	assert_eq(birds, 8, "птиц")
	assert_eq(critters, 6, "зверьков")
	assert_eq(fireflies, 3, "светлячков")
	assert_eq(water, 2, "море и озеро")
	assert_gt(markers, 0, "в расщелине есть HangPoint")
	assert_eq(island.zones.size(), 6, "шесть зон")
	assert_eq(
		island.spawn_zones.size(), 6,
		"точки появления всех зон (--dev-spawn)",
	)


func test_water_surfaces_configured() -> void:
	var island := ISLAND.instantiate() as Island
	add_child_autofree(island)
	for child: Node in island.get_children():
		if child is WaterArea:
			var area := child as WaterArea
			assert_gt(area.surface_size.x, 0.0, "размер задан")
			assert_almost_eq(
				area.level(), IslandGen.SEA_LEVEL, 0.01, "уровень воды из генератора",
			)


func test_player_stands_in_every_spawn_zone() -> void:
	# Коллизия GridMap работает: персонаж не проваливается ни в одной зоне.
	var island := ISLAND.instantiate() as Island
	add_child_autofree(island)
	var player := PLAYER.instantiate() as Player
	island.add_child(player)
	for zone: String in island.spawn_zones:
		var spawn: Vector3 = island.spawn_point(zone)
		player.global_position = spawn
		await get_tree().physics_frame
		var settled := false
		for i: int in range(60):
			await get_tree().physics_frame
			if player.is_on_floor():
				settled = true
				break
		assert_true(settled, "в зоне %s персонаж встал на землю" % zone)
		assert_almost_eq(
			player.global_position.y,
			spawn.y, 0.4,
			"в зоне %s стоит на поверхности, а не падает" % zone,
		)
	player.queue_free()


func test_static_coin_collected_by_touch() -> void:
	var island := ISLAND.instantiate() as Island
	add_child_autofree(island)
	var coin := island.get_node("Coin1") as CoinPickup
	var player := PLAYER.instantiate() as Player
	island.add_child(player)
	player.global_position = coin.position + Vector3(0.0, 0.2, 0.0)
	var coins_before: int = Session.world_coins
	for i: int in range(60):
		await get_tree().physics_frame
		if not coin.visible:
			break
	assert_false(coin.visible, "монета скрыта после подбора")
	assert_eq(Session.world_coins, coins_before + B.coin_reward, "+1 монета касанием")
	player.queue_free()


func test_player_attack_kills_bird() -> void:
	var world := Node3D.new()
	add_child_autofree(world)
	var bird := Bird.new()
	bird.spawn_id = 99
	bird.motion = {
		"center": Vector3(0.0, 3.0, 0.0),
		"radius": 6.0,
		"height": 0.8,
		"period": 600.0,
		"phase": 0.0,
		"direction": 1,
	}
	world.add_child(bird)
	var player := PLAYER.instantiate() as Player
	world.add_child(player)
	# Площадка под ногами, чтобы персонаж не улетел вниз за время удара.
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(6.0, -0.5, 0.0)
	world.add_child(floor_body)
	# Зона удара — на 0.8 м выше ступней и 0.9 м впереди по +Z.
	var bird_pos := MobMotion.bird_position(bird.motion, Session.world_time)
	player.global_position = bird_pos + Vector3(0.0, -0.8, -0.9)
	await get_tree().physics_frame
	var coins_before: int = Session.world_coins
	var killed: Array[int] = []
	EventBus.mob_killed.connect(
		func(id: int, _killer: int, _respawn: float) -> void: killed.append(id),
		CONNECT_ONE_SHOT,
	)
	player._try_attack()
	for i: int in range(30):
		await get_tree().physics_frame
		if not bird.visible:
			break
	assert_false(bird.visible, "птица исчезла после удара")
	assert_eq(Session.world_coins, coins_before + B.bird_reward, "+1 монета за птицу")
	assert_eq(killed, [99], "событие mob_killed с spawn_id")
	player.queue_free()


func test_firefly_survives_single_hit() -> void:
	# Раздел 8: светлячок уязвим только для ударов двоих — один удар бессилен
	# (полная механика «двое в 3 с» — П5).
	var world := Node3D.new()
	add_child_autofree(world)
	var firefly := GoldenFirefly.new()
	firefly.motion = {
		"center": Vector3(0.0, 2.0, 0.0), "drift": 1.0, "period": 5.0, "phase": 0.0,
	}
	world.add_child(firefly)
	var coins_before: int = Session.world_coins
	firefly.take_hit()
	assert_true(firefly.visible, "светлячок жив после одного удара")
	assert_eq(Session.world_coins, coins_before, "монет не начислено")
