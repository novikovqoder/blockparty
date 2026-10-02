# Обязательный тест этапа П1 (разделы 5, 17, 18 SPEC): параметры прыжка —
# высота в пределах 1.3–1.5 м («на один блок да, на два — нет»), переменная
# высота при отпускании, предел падения, скорости шага/бега, автоподъём
# только на полублоки. Аналитика (JumpMath) сверяется с пошаговой симуляцией
# и с реальной физикой персонажа на площадке (интеграционные тесты).
extends GutTest

const B: Balance = preload("res://gameplay/balance.tres")
const PLAYER: PackedScene = preload("res://gameplay/player/player.tscn")

const EPS: float = 0.01


func test_apex_height_in_spec_range() -> void:
	var apex := JumpMath.apex_height(B)
	assert_between(apex, 1.3, 1.5, "высота прыжка 1.3–1.5 м (раздел 5)")
	assert_gte(apex, 1.05, "на ступень в 1 блок запрыгивается")
	assert_lt(apex, 1.95, "на 2 блока не запрыгивается")


func test_simulation_matches_analytic_apex() -> void:
	var result := JumpMath.simulate_jump(B)
	# Пошаговая схема (полунеявный Эйлер, шаг 1/60) недобирает высоту
	# против аналитики на ~0.06 — та же схема у move_and_slide, поэтому
	# фактическая высота в игре ближе к симуляции, допускаем 0.08.
	assert_almost_eq(float(result["apex"]), JumpMath.apex_height(B), 0.08,
		"симуляция тем же кодом, что и игра")
	assert_between(float(result["apex"]), 1.3, 1.5, "и в пределах 1.3–1.5")
	assert_lte(float(result["fall_speed_max"]), B.max_fall_speed, "предел падения")
	assert_gt(float(result["fall_speed_max"]), B.jump_speed,
		"падение быстрее подъёма (гравитация ×1.3)")


func test_jump_cut_makes_jump_lower() -> void:
	var full := JumpMath.simulate_jump(B)
	var cut := JumpMath.simulate_jump(B, 0.5)
	assert_lt(float(cut["apex"]), float(full["apex"]) - 0.2,
		"отпускание кнопки срезает высоту")


func test_locomotion_speeds_from_spec() -> void:
	assert_between(B.run_speed, 6.0, 7.0, "бег 6.5 м/с")
	assert_between(B.walk_speed, 2.0, 3.0, "шаг 2.5 м/с")
	assert_gt(B.run_speed, B.walk_speed)


func test_step_up_is_for_half_blocks_only() -> void:
	assert_between(B.step_up_height, 0.5, 0.999,
		"автоподъём покрывает полублоки, но не блок")


# --- Интеграционные: реальная физика CharacterBody3D ---

func _box(parent: Node3D, size: Vector3, center: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	parent.add_child(body)


func _floor(parent: Node3D) -> void:
	_box(parent, Vector3(24, 1, 24), Vector3(0, -0.5, 0))


func _player_on(parent: Node3D, position: Vector3) -> Player:
	var player := PLAYER.instantiate() as Player
	parent.add_child(player)
	player.global_position = position
	return player


# Origin персонажа — в ногах: «стоит на полу» это y ≈ 0, апекс прыжка ≈ 1.34.
# Перед вводом даём 3 кадра осесть на пол, иначе буфер прыжка истекает
# раньше приземления (buffer 0.1 с — падение 0.85 м длится дольше).
func _settle() -> void:
	for i: int in range(3):
		await get_tree().physics_frame


func test_jump_onto_one_block_integrated() -> void:
	var world := Node3D.new()
	add_child_autofree(world)
	_floor(world)
	_box(world, Vector3(2, 1, 2), Vector3(0, 0.5, -3))
	# Старт в 2.2 м от грани блока: к моменту касания стены апекс пройден
	# не успеет упасть ниже верха блока (1.0).
	var player := _player_on(world, Vector3(0, 0.05, 0.2))
	await _settle()
	Input.action_press("move_forward")
	Input.action_press("jump")
	var top: float = 0.0
	for i: int in range(150):
		await get_tree().physics_frame
		top = maxf(top, player.global_position.y)
	Input.action_release("move_forward")
	Input.action_release("jump")
	assert_gte(top, 1.2, "запрыгнул: ноги поднялись выше блока (1.0)")


func test_cannot_jump_onto_two_blocks_integrated() -> void:
	var world := Node3D.new()
	add_child_autofree(world)
	_floor(world)
	_box(world, Vector3(2, 2, 2), Vector3(0, 1.0, -3))
	var player := _player_on(world, Vector3(0, 0.05, 0.2))
	await _settle()
	Input.action_press("move_forward")
	Input.action_press("jump")
	var top: float = 0.0
	for i: int in range(150):
		await get_tree().physics_frame
		top = maxf(top, player.global_position.y)
	Input.action_release("move_forward")
	Input.action_release("jump")
	# Верх блока 2.0, апекс прыжка с пола ≈ 1.35 — не хватает.
	assert_lt(top, 1.9, "на 2 блока с земли не запрыгнуть")
