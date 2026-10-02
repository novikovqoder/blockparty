# Интеграционные тесты объектов площадки П1 (раздел 6 SPEC): вода — персонаж
# плавает на поверхности, плита — нажимается стоящим игроком. Числа плавания
# и хода плиты — в balance.tres, здесь проверяется поведение узлов.
extends GutTest

const PLAYER: PackedScene = preload("res://gameplay/player/player.tscn")

const EPS: float = 0.15


func _box(parent: Node3D, size: Vector3, center: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	parent.add_child(body)


func _player_on(parent: Node3D, position: Vector3) -> Player:
	var player := PLAYER.instantiate() as Player
	parent.add_child(player)
	player.global_position = position
	return player


func test_swimming_on_water_surface() -> void:
	var world := Node3D.new()
	add_child_autofree(world)
	# Дно пруда на −2, вода на уровне −0.2, берег не нужен.
	_box(world, Vector3(12, 1, 12), Vector3(0, -2.5, 0))
	var water := WaterArea.new()
	world.add_child(water)
	water.setup(Vector2(0, 0), Vector2(8, 8), -0.2)
	var player := _player_on(world, Vector3(0, 0.5, 0))
	var surfaced := false
	for i: int in range(120):
		await get_tree().physics_frame
		# Origin в ногах: уровень (−0.2) − погружение (0.7) = −0.9.
		if player.in_water() and absf(player.global_position.y + 0.9) < EPS:
			surfaced = true
			break
	assert_true(player.in_water(), "в зоне воды")
	assert_true(surfaced, "плавает на поверхности (ноги ≈ −0.9)")
	# Скорость в воде ограничена шагом — прямая проверка формулы игрока.
	assert_lt(absf(player.velocity.y), 3.0, "вертикальная скорость плавная")


func test_pressure_plate_pressed_by_player() -> void:
	var world := Node3D.new()
	add_child_autofree(world)
	_box(world, Vector3(12, 1, 12), Vector3(0, -0.5, 0))
	var plate: PressurePlate = load("res://gameplay/activities/pressure_plate.tscn").instantiate()
	world.add_child(plate)
	plate.position = Vector3(0, 0, 0)
	var player := _player_on(world, Vector3(0, 1.3, 0))
	var pressed := false
	for i: int in range(60):
		await get_tree().physics_frame
		if plate.is_pressed():
			pressed = true
			break
	assert_true(pressed, "плита нажата стоящим игроком")
	# Сходим с плиты — отпускает.
	player.global_position = Vector3(5, 1.0, 0)
	var released := false
	for i: int in range(60):
		await get_tree().physics_frame
		if not plate.is_pressed():
			released = true
			break
	assert_true(released, "плита отпустила")
