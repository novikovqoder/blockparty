# Тест Д2 (этап 0 закрытия П5.8): скольжение после приземления. Сценарий
# владельца на физическом игроке — бег (W зажата), прыжок, W НЕ отпускать,
# 2 с после приземления; то же с шагом (W+Shift); и приземление в стойку
# (поза ленда там уместна и должна сохраниться). Проверки — покадрово в
# RealismCheck.check_landing_blend: при приземлении с горизонтальной
# скоростью поза ленда (статичный присед) не играется ни кадра — с кадра
# касания модель блендится в локомоцию (кросс-фейд ANIM_BLEND = 0.15 с),
# покой — только при скорости ≈ 0. До этапа 0 ленд играл ~0.2 с при беге
# 6.5 м/с (тело проезжало ~1.3 м со скольжением) — тест падал.
extends GutTest

const PLAYER: PackedScene = preload("res://gameplay/player/player.tscn")


func _box(parent: Node3D, size: Vector3, center: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	parent.add_child(body)


## Игрок с собранной моделью на чистой площадке 60×60 (без препятствий —
## направление бега не важно, raycast RealismCheck выберет любое).
func _player_ready() -> Player:
	var world := Node3D.new()
	add_child_autofree(world)
	_box(world, Vector3(60, 1, 60), Vector3(0, -0.5, 0))
	var player := PLAYER.instantiate() as Player
	world.add_child(player)
	player.global_position = Vector3(0, 0.05, 0)
	player.visual.setup_appearance(Appearance.default_for(0))
	for i: int in range(5):
		await get_tree().physics_frame
	return player


func _check(mode: String) -> void:
	var player := await _player_ready()
	var result: Dictionary = await RealismCheck.check_landing_blend(
		player, mode, true)
	assert_true(result["ok"], "check_landing_blend(%s): %s"
		% [mode, " | ".join(result["reasons"])])


func test_landing_run_blends_into_locomotion() -> void:
	await _check("run")


func test_landing_walk_blends_into_locomotion() -> void:
	await _check("walk")


func test_landing_in_place_keeps_land_pose() -> void:
	await _check("still")
