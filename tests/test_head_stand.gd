# Обязательный тест этапа П1 (разделы 5, 17, 18 SPEC): условие коллизии
# головы — на голову можно встать только падая сверху (ступни выше верхней
# грани бокса), нельзя упереться сбоку; прыжок с головы с усилением ×1.3
# хватает на уступ в 3 блока. Аналитика + интеграционные тесты реальной
# физики двух персонажей.
extends GutTest

const B: Balance = preload("res://gameplay/balance.tres")
const PLAYER: PackedScene = preload("res://gameplay/player/player.tscn")


func test_can_stand_conditions() -> void:
	var eps := B.head_stand_epsilon
	assert_true(HeadStand.can_stand(1.75, 1.7, -2.0, eps), "падаю сверху")
	assert_false(HeadStand.can_stand(1.75, 1.7, 2.0, eps), "взлетаю — столкновения нет")
	assert_false(HeadStand.can_stand(1.4, 1.7, -2.0, eps), "ступни ниже грани — упереться сбоку нельзя")
	assert_true(HeadStand.can_stand(1.68, 1.7, -0.01, eps), "допуск кадра контакта")


func test_head_jump_reaches_three_blocks() -> void:
	var reach := HeadStand.head_jump_reach(B)
	assert_between(reach, 3.6, 4.3, "рост 1.6 + усиленный прыжок ~2.4 м")
	assert_lt(JumpMath.apex_height(B), 3.0, "с земли уступ в 3 блока не взять")


# --- Интеграционные: два персонажа на площадке ---

func _floor(parent: Node3D) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(24, 1, 24)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0, -0.5, 0)
	parent.add_child(body)


func _player_on(parent: Node3D, position: Vector3) -> Player:
	var player := PLAYER.instantiate() as Player
	parent.add_child(player)
	player.global_position = position
	return player


# Origin персонажа — в ногах (коллайдер поднят на половину роста внутри
# player.tscn), поэтому «стоит на полу» — это y ≈ 0, а «встал на голову» —
# ноги на верхней грани бокса головы 1.7.
const GROUND_Y: float = 0.0


func test_fall_onto_head_lands_and_boosts() -> void:
	var world := Node3D.new()
	add_child_autofree(world)
	_floor(world)
	var below := _player_on(world, Vector3(0, 0.05, 0))
	var above := _player_on(world, Vector3(0, 3.0, 0))
	# Падение сверху: останавливается на коллайдере головы (верх 1.7).
	var settled: bool = false
	for i: int in range(120):
		await get_tree().physics_frame
		if above.is_on_floor() and absf(above.global_position.y - 1.7) < 0.1:
			settled = true
			break
	assert_true(settled, "встал на голову: ноги на верхней грани бокса 1.7")
	assert_almost_eq(below.global_position.y, GROUND_Y, 0.05, "нижний стоит на месте")

	# Прыжок с головы усилен ×1.3: апекс 1.7 + ~2.4 ≈ 4.1 — хватает на
	# уступ в 3 блока (3.0), без усиления (1.3 + 1.7 = 3.0 впритык) — нет.
	Input.action_press("jump")
	var top: float = above.global_position.y
	for i: int in range(60):
		await get_tree().physics_frame
		top = maxf(top, above.global_position.y)
	Input.action_release("jump")
	assert_gt(top, 3.5, "прыжок с головы достаёт уступ в 3 блока")
	assert_lt(JumpMath.apex_height(B) + 1.7, 3.5, "без усиления так высоко нельзя")


func test_fall_beside_head_passes_through() -> void:
	var world := Node3D.new()
	add_child_autofree(world)
	_floor(world)
	var below := _player_on(world, Vector3(0, 0.05, 0))
	# Сбоку: капсула пересекает бокс головы по x, но ступни (1.0) ниже
	# грани (1.7) — упереться нельзя, пролетаем насквозь до пола.
	var beside := _player_on(world, Vector3(0.45, 1.0, 0))
	var landed := false
	for i: int in range(120):
		await get_tree().physics_frame
		if beside.is_on_floor() and absf(beside.global_position.y - GROUND_Y) < 0.08:
			landed = true
			break
	assert_true(landed, "прошёл сквозь голову сбоку и упал на пол")
	assert_almost_eq(below.global_position.y, GROUND_Y, 0.05, "нижний стоит на месте")
