# Тесты RemotePlayer (этап П3): снапшоты применяются буфером, render
# интерполирует позицию между двумя снапшотами (задержка 100 мс), поворот
# идёт по кратчайшей дуге (не через 0 при переходе через π), ник и коллайдер
# головы на месте, старый seq отбрасывается. Логика буфера отдельно —
# test_snapshot_buffer.gd; здесь проверка узла целиком.
extends GutTest


func _make_remote() -> RemotePlayer:
	var remote := RemotePlayer.new()
	remote.setup(7, "Тест")
	add_child_autofree(remote)
	return remote


func _snap(seq: int, x: float, yaw: float, anim: int = 0) -> Dictionary:
	return {
		"seq": seq,
		"x": x,
		"y": 0.0,
		"z": 0.0,
		"yaw": yaw,
		"vx": 0.0,
		"vy": 0.0,
		"vz": 0.0,
		"anim": anim,
		"flags": 0,
	}


func test_model_matches_character_number() -> void:
	# Шаг 8 П4.6: модель ремоута — персонаж, выбранный игроком (пришёл
	# с rpc_player_joined), а не хэш peer id. Мусорный номер клампится.
	var remote := RemotePlayer.new()
	remote.setup(7, "Тест", 2)
	add_child_autofree(remote)
	var visual := remote.get_node("Model/CharacterModel") as CharacterModel
	assert_eq(visual.character, 2, "третий персонаж")
	var junk := RemotePlayer.new()
	junk.setup(8, "Мусор", 17)
	add_child_autofree(junk)
	assert_eq(
		(junk.get_node("Model/CharacterModel") as CharacterModel).character,
		CharacterModel.count() - 1,
		"номер вне диапазона клампится к последнему"
	)


func test_node_has_name_and_head_collider() -> void:
	var remote := _make_remote()
	assert_eq(remote.player_name, "Тест", "ник сохранён")
	var label := remote.get_node_or_null("NameLabel") as Label3D
	assert_not_null(label, "ник — Label3D над головой")
	if label != null:
		assert_eq(label.text, "Тест", "текст ника")
	var head := remote.get_node_or_null("HeadTop") as AnimatableBody3D
	assert_not_null(head, "коллайдер головы на месте")
	if head != null:
		assert_eq(head.collision_layer, 1 << (HeadStand.LAYER_HEAD - 1), "слой голов")
		assert_eq(int(head.get_meta("peer_id")), 7, "метка peer_id для подсадки")


func test_render_interpolates_between_snapshots() -> void:
	var remote := _make_remote()
	remote.apply_snapshot(_snap(1, 0.0, 0.0), 1000)
	remote.apply_snapshot(_snap(2, 10.0, 0.0), 1100)
	# Отрисовка на «сейчас» = 1150: буфер сэмплит 1150 − 100 = 1050,
	# ровно середина между снапшотами.
	remote.render(1150)
	assert_almost_eq(remote.global_position.x, 5.0, 0.01, "позиция — середина отрезка")


func test_render_takes_shortest_yaw_arc() -> void:
	var remote := _make_remote()
	remote.apply_snapshot(_snap(1, 0.0, 3.0), 1000)
	remote.apply_snapshot(_snap(2, 10.0, -3.0), 1100)
	remote.render(1150)
	# Через π, а не через 0: 3.0 → −3.0 по дуге проходит 3.14 в середине.
	var yaw: float = remote.get_node("Model").rotation.y
	assert_almost_eq(absf(yaw), PI, 0.01, "поворот по кратчайшей дуге")


func test_old_seq_snapshot_is_ignored() -> void:
	var remote := _make_remote()
	remote.apply_snapshot(_snap(5, 50.0, 0.0), 1000)
	remote.apply_snapshot(_snap(2, 0.0, 0.0), 1100)
	remote.render(1200 + Protocol.INTERP_DELAY_MS)
	assert_almost_eq(remote.global_position.x, 50.0, 0.01, "старый seq не откатил позицию")


func test_last_position_before_any_snapshot() -> void:
	var remote := _make_remote()
	remote.render(1000)
	assert_eq(remote.global_position, Vector3.ZERO, "без снапшотов — стоит в нуле")
