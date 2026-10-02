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
	assert_true(logic.tick(0.1), "10 с — время вышло")
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
	# Пол вокруг ямы 4×4 в центре (x и z от −2 до 2), глубина 4.
	_box(world, Vector3(24, 1, 24), Vector3(0, -0.5, 4))
	_box(world, Vector3(24, 1, 24), Vector3(0, -0.5, -4))
	_box(world, Vector3(4, 1, 24), Vector3(0, -0.5, 0))
	_box(world, Vector3(4, 1, 4), Vector3(0, -4.5, 0))
	# Зона расщелины чуть ниже кромки (центр −2, высота 3 → верх −0.5),
	# точки HangPoint на кромке (глобально y = 0), камень на берегу.
	var area := HangArea.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.6, 3.0, 3.6)
	shape.shape = box
	area.add_child(shape)
	for point: Vector3 in [Vector3(0, 2.0, -1.8), Vector3(0, 2.0, 1.8)]:
		var marker := Marker3D.new()
		marker.position = point
		area.add_child(marker)
	world.add_child(area)
	area.global_position = Vector3(0, -2.0, 0)
	var stone := RespawnStone.new()
	world.add_child(stone)
	stone.global_position = Vector3(6, 0, 4)

	var player := PLAYER.instantiate() as Player
	world.add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	await get_tree().physics_frame
	# Ускоряем тест: вместо 10 с висения — полсекунды (логика та же).
	var saved_hang_time := B.hang_time
	B.hang_time = 0.5
	var hang_started := false
	EventBus.player_hang_started.connect(func(_left: float) -> void: hang_started = true)
	for i: int in range(90):
		await get_tree().physics_frame
		if hang_started:
			break
	assert_true(hang_started, "падение в яму — цепляние за край")
	# Висит у точки: центр = точка (0, 0, ±1.8) + сдвиг −0.2.
	assert_almost_eq(player.global_position.y, -0.2, 0.1)
	assert_almost_eq(absf(player.global_position.z), 1.8, 0.1)

	var respawned := false
	EventBus.player_respawned.connect(func() -> void: respawned = true)
	for i: int in range(90):
		await get_tree().physics_frame
		if respawned:
			break
	B.hang_time = saved_hang_time
	assert_true(respawned, "через hang_time — перенос")
	assert_almost_eq(player.global_position.x, 6.0, 0.15, "у Камня духа")
	assert_almost_eq(player.global_position.z, 4.0, 0.15)
