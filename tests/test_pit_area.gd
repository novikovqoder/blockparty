# Тест пропасти (разделы 5, 7.1): края зацепа задаются в локальных
# координатах секции (Chunk.add_pit), а игроку enter_hang нужна мировая —
# PitArea переводит точку через трансформ чанка. Регрессия бага «после
# падения в пропасть игрок висел на offset_x левее настоящего края».
extends GutTest

const PLAYER_SCENE: PackedScene = preload("res://gameplay/player/player.tscn")


## Пропасть 1600..1792 внутри секции со смещением offset_x.
func _pit_under_chunk(offset_x: float) -> PitArea:
	var chunk := Node2D.new()
	chunk.position = Vector2(offset_x, 0.0)
	add_child_autofree(chunk)
	var pit := PitArea.new()
	pit.setup(Rect2(1600.0, 576.0, 192.0, 144.0), [Vector2(1600.0, 576.0)])
	chunk.add_child(pit)
	return pit


func test_enter_hang_uses_world_edge() -> void:
	var pit := _pit_under_chunk(1152.0)
	var player := PLAYER_SCENE.instantiate()
	pit.get_parent().add_child(player)
	player.global_position = Vector2(2800.0, 640.0)  # упал в пропасть
	pit._on_body_entered(player)
	assert_almost_eq(player.global_position.x, 2759.0, 0.01, "висит у мирового края пропасти (2752 + 7)")
	assert_almost_eq(player.global_position.y, 590.0, 0.01)
	assert_true(player.is_hanging())
	player.queue_free()


func test_enter_hang_without_offset() -> void:
	# Секция без смещения (offset 0) — край там, где задан.
	var pit := _pit_under_chunk(0.0)
	var player := PLAYER_SCENE.instantiate()
	pit.get_parent().add_child(player)
	player.global_position = Vector2(1700.0, 640.0)
	pit._on_body_entered(player)
	assert_almost_eq(player.global_position.x, 1607.0, 0.01)
	player.queue_free()


func test_nearest_left_edge_of_several() -> void:
	# medium_movers: две пропасти — зацеп за ближайший левый край.
	var chunk := Node2D.new()
	chunk.position = Vector2(1000.0, 0.0)
	add_child_autofree(chunk)
	var pit := PitArea.new()
	pit.setup(
		Rect2(1536.0, 576.0, 128.0, 144.0),
		[Vector2(704.0, 576.0), Vector2(1536.0, 576.0)]
	)
	chunk.add_child(pit)
	var player := PLAYER_SCENE.instantiate()
	chunk.add_child(player)
	player.global_position = Vector2(2560.0, 640.0)  # упал во вторую пропасть
	pit._on_body_entered(player)
	assert_almost_eq(player.global_position.x, 2543.0, 0.01, "держится за край 2536 + 7")
	player.queue_free()
