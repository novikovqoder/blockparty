# Звездопад (раздел 7 SPEC, П5): звёзды падают 2 минуты после зажжения
# всех маяков — позиции детерминированы от (старт, индекс) RandomNumber
# Generator'ом с явным seed (правило проекта: генерация без randf()),
# живут star_lifetime, подбор — «кто первый» (хост), узлы создаёт
# и убирает Starfall по сигналам beacons_state/star_taken.
extends GutTest

const B: Balance = preload("res://gameplay/balance.tres")

const EPS: float = 0.001


func test_star_indices_window() -> void:
	# elapsed=0: только что родилась первая (её видно сразу).
	assert_eq(Starfall.star_indices(0.0, B), [0], "старт — первая звезда")
	# Полетели: 5 с при интервале 1.5 — живы индексы 0..3.
	var mid: Array[int] = Starfall.star_indices(5.0, B)
	assert_eq(mid[0], 0)
	assert_eq(mid[mid.size() - 1], int(5.0 / B.star_interval))
	# Первая истлела (lifetime прошёл): 13 с — начинаются с 1.
	assert_eq(Starfall.star_indices(13.0, B)[0], 1, "звезда 0 истлела")
	# После конца Звездопада новые не рождаются, старые доживают.
	var after_end: Array[int] = Starfall.star_indices(B.starfall_duration + 1.0, B)
	assert_eq(
		after_end[after_end.size() - 1],
		int(B.starfall_duration / B.star_interval),
		"последний рождённый индекс — на границе duration",
	)
	var expired: Array[int] = Starfall.star_indices(
		B.starfall_duration + B.star_lifetime + 1.0, B
	)
	assert_eq(expired.size(), 0, "все истлели")


func test_star_position_deterministic() -> void:
	# Одинаковые аргументы — одинаковая точка у всех клиентов и хоста.
	assert_eq(Starfall.star_position(400.0, 3), Starfall.star_position(400.0, 3))
	# Разные звёзды падают в разные места.
	assert_ne(Starfall.star_position(400.0, 3), Starfall.star_position(400.0, 4))
	# Новый цикл (другой старт) — новое небо.
	assert_ne(Starfall.star_position(400.0, 3), Starfall.star_position(1500.0, 3))
	# В пределах острова (раздел 6: половина 128 м, звёзды — по суше).
	for index: int in 10:
		var pos := Starfall.star_position(400.0, index)
		assert_between(pos.x, -float(IslandGen.HALF), float(IslandGen.HALF))
		assert_between(pos.z, -float(IslandGen.HALF), float(IslandGen.HALF))


func test_starfall_manager_spawns_and_takes() -> void:
	var world := Node3D.new()
	add_child_autofree(world)
	var starfall := Starfall.new()
	world.add_child(starfall)
	# Часы мира — на 5 с после старта: живы индексы 0..3.
	Session.world_time = 100.0
	EventBus.beacons_state.emit([0, 1, 2, 3, 4], [], 95.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var stars := starfall.get_children().filter(
		func(child: Node) -> bool: return child is StarPickup
	)
	assert_eq(stars.size(), 4, "звёзды 0..3 созданы")
	# Хост подтвердил подбор звезды 2 — она исчезает и не возрождается.
	EventBus.star_taken.emit(2, 1)
	await get_tree().process_frame
	stars = starfall.get_children().filter(
		func(child: Node) -> bool: return child is StarPickup
	)
	assert_eq(stars.size(), 3, "подобранная звезда исчезла")
	# Время идёт: истлевшая (0-я, born 95 + lifetime) убрана, новые родились.
	Session.world_time = 95.0 + B.star_lifetime + 0.2
	await get_tree().process_frame
	await get_tree().process_frame
	var alive: Array[int] = []
	for child: Node in starfall.get_children():
		if child is StarPickup:
			alive.append((child as StarPickup).index)
	assert_false(alive.has(0), "истлевшая убрана")
	assert_false(alive.has(2), "подобранная не возродилась")
	assert_true(alive.has(1), "живая осталась")
	# Гашение маяков (конец цикла) — небо пустое.
	EventBus.beacons_state.emit([], [], -1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(
		starfall.get_children().filter(
			func(child: Node) -> bool: return child is StarPickup
		).size(),
		0,
		"после сброса звёзд нет",
	)
	Session.world_time = 0.0
