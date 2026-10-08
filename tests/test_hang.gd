# Обязательный тест этапа П1 (разделы 9.1, 17, 18 SPEC): состояние «Висит» —
# логика таймера 10 с и выбор ближайшей точки HangPoint, интеграционно:
# падение в CrevasseArea цепляет за край, по истечении времени — перенос
# к Камню духа без штрафа. Вытягивание другим игроком — этап П5.
extends GutTest

const B: Balance = preload("res://gameplay/balance.tres")
const PLAYER: PackedScene = preload("res://gameplay/player/player.tscn")

const EPS: float = 0.01


func test_hang_logic_expires_after_10s() -> void:
	var logic := HangLogic.new()
	logic.start(B.hang_time)
	assert_true(logic.hanging)
	for i: int in range(99):
		assert_false(logic.tick(0.1), "тик %d: ещё висит" % i)
	assert_true(logic.hanging, "9.9 с — висит")
	# Граница 10.0 с — с допуском: 100 вычитаний 0.1 в float могут
	# оставить ~1e-15 хвоста, рвём его одним «крупным» тиком.
	assert_true(logic.tick(0.2), "10.1 с — время вышло")
	assert_false(logic.hanging)


func test_hang_logic_stop_resets() -> void:
	var logic := HangLogic.new()
	logic.start(10.0)
	logic.stop()
	assert_false(logic.hanging)
	assert_false(logic.tick(0.5), "после stop перенос не требуется")


func test_nearest_point_to_fallen_player() -> void:
	var points: Array[Vector3] = [
		Vector3(10, 0, 0),
		Vector3(0, 0, 5),
		Vector3(-3, 0, 0),
	]
	var nearest := HangLogic.nearest_point(points, Vector3(2, 0, 0))
	assert_almost_eq(nearest.x, -3.0, EPS)
	assert_almost_eq(nearest.z, 0.0, EPS)


# --- Интеграционный: яма, точки и Камень духа ---

func _box(parent: Node3D, size: Vector3, center: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	parent.add_child(body)


func test_fall_into_crevasse_hangs_then_respawns() -> void:
	var world := Node3D.new()
	add_child_autofree(world)
	# Пол вокруг ямы 4×4 в центре (x и z от −2 до 2), дно на глубине 4:
	# четыре плиты по сторонам + дно, центр открыт — игрок в (0, 1, 0)
	# падает сквозь него в HangArea.
	_box(world, Vector3(8, 1, 20), Vector3(-6, -0.5, 0))
	_box(world, Vector3(8, 1, 20), Vector3(6, -0.5, 0))
	_box(world, Vector3(4, 1, 8), Vector3(0, -0.5, 6))
	_box(world, Vector3(4, 1, 8), Vector3(0, -0.5, -6))
	_box(world, Vector3(4.4, 0.5, 4.4), Vector3(0, -4.25, 0))
	# Зона расщелины чуть ниже кромки (центр −2, высота 3 → верх −0.5),
	# точки HangPoint на кромке (глобально y = 0), камень на берегу.
	var area := HangArea.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.6, 3.0, 3.6)
	shape.shape = box
	area.add_child(shape)
	for point: Vector3 in [Vector3(0, 2.0, -1.8), Vector3(0, 2.0, 1.8)]:
		var hang_point := HangPoint.new()
		hang_point.position = point
		area.add_child(hang_point)
	world.add_child(area)
	area.global_position = Vector3(0, -2.0, 0)
	var stone := RespawnStone.new()
	world.add_child(stone)
	stone.global_position = Vector3(6, 0, 4)

	var player := PLAYER.instantiate() as Player
	world.add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	await get_tree().physics_frame
	# Лямбды GDScript захватывают локальные переменные по значению, поэтому
	# флаг — ячейка массива (мутация объекта видна снаружи).
	var hang_started: Array[bool] = [false]
	EventBus.player_hang_started.connect(
		func(_left: float) -> void: hang_started[0] = true,
	)
	for i: int in range(90):
		await get_tree().physics_frame
		if hang_started[0]:
			break
	assert_true(hang_started[0], "падение в яму — цепляние за край")
	# Висит у точки: центр = точка (0, 0, ±1.8) + сдвиг −0.2.
	assert_almost_eq(player.global_position.y, -0.2, 0.1)
	assert_almost_eq(absf(player.global_position.z), 1.8, 0.1)

	# Ускоряем истечение без мутации общего balance.tres: в GUT-окружении
	# значения .tres возвращаются к дефолтам скрипта на следующем кадре,
	# поэтому списываем остаток напрямую — сам таймер честно дотикает
	# в _physics_process (логика 10 с покрыта тестом выше).
	player._hang_left = 0.3
	var respawned: Array[bool] = [false]
	EventBus.player_respawned.connect(func() -> void: respawned[0] = true)
	for i: int in range(90):
		await get_tree().physics_frame
		if respawned[0]:
			break
	assert_true(respawned[0], "через hang_time — перенос")
	assert_almost_eq(player.global_position.x, 6.0, 0.15, "у Камня духа")
	assert_almost_eq(player.global_position.z, 4.0, 0.15)


# --- Вытягивание (раздел 9.1, П5) ---

## Вытянутый поднимается на кромку в точку цепляния и больше не висит:
## сам переносит тело, хост только подтвердил событие (rpc_pulled).
func test_pulled_up_returns_to_edge() -> void:
	var world := Node3D.new()
	add_child_autofree(world)
	var player := PLAYER.instantiate() as Player
	world.add_child(player)
	await get_tree().physics_frame
	var edge := Vector3(5.0, 0.0, 5.0)
	player.start_hang(edge)
	assert_true(player.is_hanging())
	player.pulled_up()
	assert_false(player.is_hanging())
	assert_almost_eq(player.global_position.x, edge.x, EPS, "вернулся на кромку")
	assert_almost_eq(player.global_position.y, edge.y + 0.05, EPS)
	assert_almost_eq(player.global_position.z, edge.z, EPS)
	# Повторное подтверждение (поздний пакет) — не телепортирует.
	player.pulled_up()
	assert_almost_eq(player.global_position.x, edge.x, EPS)


## Сила помощника ускоряет вытягивание (раздел 17): удержание E делится
## на множитель Силы — сильный тянет быстрее, но вытянуть может любой.
func test_pull_hold_time_scales_with_strength() -> void:
	var point := HangPoint.new()
	add_child_autofree(point)
	var player := PLAYER.instantiate() as Player
	add_child(player)
	await get_tree().physics_frame
	var seen: Array[int] = []
	for character: int in CharacterModel.count():
		player.apply_stats(character)
		var strength: int = player.strength()
		assert_between(strength, 1, 5)
		assert_almost_eq(
			point.hold_time(player),
			B.pull_hold_time / B.strength_multipliers[strength - 1],
			0.001,
			"удержание идёт множителем Силы персонажа %d" % character,
		)
		if not seen.has(strength):
			seen.append(strength)
	assert_gt(seen.size(), 1, "персонажи различаются по Силе — тест содержателен")
	player.queue_free()
