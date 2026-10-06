# Тесты данных персонажей (раздел 16, шаги 5–6 П4.6): characters.json полон
# и на двух языках, характеристики соблюдают правила (1–5, сумма 9, каждый
# лучший ровно в одной), множители из balance.tres применяются к игроку,
# выбор сохраняется в user://, неверный номер читается как первый.
extends GutTest

const B: Balance = preload("res://gameplay/balance.tres")
const PLAYER_SCENE: PackedScene = preload("res://gameplay/player/player.tscn")
const STAT_KEYS: PackedStringArray = ["strength", "speed", "jump"]
const TEXT_FIELDS: PackedStringArray = ["name", "motto", "description", "loves"]
const LOCALES: PackedStringArray = ["ru", "en"]


func test_all_three_have_full_data() -> void:
	assert_eq(CharacterData.count(), 3, "три персонажа")
	for index: int in CharacterData.count():
		var entry := CharacterData.get_character(index)
		for field: String in TEXT_FIELDS:
			var texts: Dictionary = entry.get(field, {})
			for locale: String in LOCALES:
				assert_true(
					texts.has(locale),
					"персонаж %d: поле %s есть на %s" % [index, field, locale]
				)
				assert_false(
					String(texts.get(locale, "")).strip_edges().is_empty(),
					"персонаж %d: поле %s на %s не пустое" % [index, field, locale]
				)


func test_stats_values_and_sum() -> void:
	for index: int in CharacterData.count():
		var stats := CharacterData.stats(index)
		var sum: int = 0
		for key: String in STAT_KEYS:
			var value := int(stats[key])
			assert_between(value, 1, 5, "персонаж %d: %s в 1–5" % [index, key])
			sum += value
		assert_eq(sum, 9, "персонаж %d: сумма характеристик 9" % index)


func test_each_best_in_exactly_one_stat() -> void:
	# Раздел 16: у каждого персонажа ровно одна характеристика, в которой он
	# лучший (строго больше всех остальных), и каждая характеристика имеет
	# ровно одного лучшего — раскладка не вырождается.
	var best_counts: Array[int] = []
	for index: int in CharacterData.count():
		var mine := CharacterData.stats(index)
		var best_count: int = 0
		for key: String in STAT_KEYS:
			var is_best := true
			for other: int in CharacterData.count():
				if other != index \
						and int(CharacterData.stats(other)[key]) >= int(mine[key]):
					is_best = false
					break
			if is_best:
				best_count += 1
		best_counts.append(best_count)
	assert_eq(best_counts, [1, 1, 1], "у каждого ровно одна «лучшая»")
	# Симметрично: каждая характеристика — ровно у одного максимума.
	for key: String in STAT_KEYS:
		var values: Array[int] = []
		for index: int in CharacterData.count():
			values.append(int(CharacterData.stats(index)[key]))
		var holders: int = 0
		for value: int in values:
			if value == values.max():
				holders += 1
		assert_eq(holders, 1, "%s: лучший ровно один" % key)


func test_stats_out_of_range_falls_back_to_first() -> void:
	# Правило CharacterModel: номер вне диапазона — первая запись.
	for bad: int in [-7, 99]:
		var stats := CharacterData.stats(bad)
		var first := CharacterData.stats(0)
		for key: String in STAT_KEYS:
			assert_eq(
				int(stats[key]), int(first[key]),
				"номер %d: %s от первого персонажа" % [bad, key]
			)


func test_apply_stats_sets_multipliers() -> void:
	# Множители 0.90–1.10 по значению характеристики (шаг 6): скорость и
	# прыжок берут свой множитель из balance.tres, сила — П5.
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	player.apply_stats(0)  # Финн 2/5/2
	assert_almost_eq(
		player.run_multiplier(), B.stat_multipliers[4], 0.0001,
		"Финн: скорость 5 → множитель 1.10"
	)
	assert_almost_eq(
		player.jump_height_multiplier(), B.stat_multipliers[1], 0.0001,
		"Финн: прыжок 2 → множитель 0.95"
	)
	player.apply_stats(1)  # Луми 3/1/5
	assert_almost_eq(
		player.run_multiplier(), B.stat_multipliers[0], 0.0001,
		"Луми: скорость 1 → множитель 0.90"
	)
	assert_almost_eq(
		player.jump_height_multiplier(), B.stat_multipliers[4], 0.0001,
		"Луми: прыжок 5 → множитель 1.10"
	)


# --- Множители в игре: реальная физика CharacterBody3D (как test_player_physics) ---

func _player_on_floor(character: int) -> Player:
	# Своя площадка на каждого персонажа: игроки не сталкиваются между собой.
	var world := Node3D.new()
	add_child_autofree(world)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(24, 1, 24)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0, -0.5, 0)
	world.add_child(body)
	var player := PLAYER_SCENE.instantiate() as Player
	world.add_child(player)
	player.global_position = Vector3(0, 0.05, 0)
	player.apply_stats(character)
	return player


func _settle() -> void:
	for i: int in range(3):
		await get_tree().physics_frame


func test_run_multiplier_applied_in_game() -> void:
	# Финн (скорость 5) и Луми (скорость 1) бегут по площадке: установившаяся
	# горизонтальная скорость — B.run_speed × множитель персонажа.
	var finn := _player_on_floor(0)
	var lumi := _player_on_floor(1)
	var finn_mult: float = B.stat_multipliers[int(CharacterData.stats(0)["speed"]) - 1]
	var lumi_mult: float = B.stat_multipliers[int(CharacterData.stats(1)["speed"]) - 1]
	await _settle()
	Input.action_press("move_forward")
	var finn_speed := 0.0
	var lumi_speed := 0.0
	for i: int in range(60):
		await get_tree().physics_frame
		finn_speed = maxf(
			finn_speed, Vector2(finn.velocity.x, finn.velocity.z).length()
		)
		lumi_speed = maxf(
			lumi_speed, Vector2(lumi.velocity.x, lumi.velocity.z).length()
		)
	Input.action_release("move_forward")
	assert_almost_eq(finn_speed, B.run_speed * finn_mult, 0.05, "Финн: бег ×множитель")
	assert_almost_eq(lumi_speed, B.run_speed * lumi_mult, 0.05, "Луми: бег ×множитель")


func test_jump_multiplier_applied_in_game() -> void:
	# Высота прыжка ∝ v², скорость — из корня множителя: отношение апексов
	# Финна и Луми равно отношению множителей (прыжок 2 против 5).
	var finn := _player_on_floor(0)
	var lumi := _player_on_floor(1)
	var finn_mult: float = B.stat_multipliers[int(CharacterData.stats(0)["jump"]) - 1]
	var lumi_mult: float = B.stat_multipliers[int(CharacterData.stats(1)["jump"]) - 1]
	await _settle()
	Input.action_press("jump")
	var finn_top := 0.0
	var lumi_top := 0.0
	for i: int in range(150):
		await get_tree().physics_frame
		finn_top = maxf(finn_top, finn.global_position.y)
		lumi_top = maxf(lumi_top, lumi.global_position.y)
	Input.action_release("jump")
	assert_gt(finn_top, 1.0, "Финн оторвался от земли")
	assert_gt(lumi_top, finn_top + 0.1, "Луми прыгает выше Финна")
	assert_almost_eq(
		lumi_top / finn_top, lumi_mult / finn_mult, 0.04,
		"отношение апексов = отношению множителей",
	)


func test_save_roundtrip_and_invalid_becomes_first() -> void:
	# Тест правит user://save.json — прежнее содержимое восстанавливается.
	var backup := ""
	if FileAccess.file_exists(Save.PATH):
		backup = FileAccess.get_file_as_string(Save.PATH)
	Save.save_character(2)
	assert_eq(Save.load_character(), 2, "выбранный третий читается обратно")
	Save.save_character(99)
	assert_eq(Save.load_character(), 2, "запись вне диапазона клампится")
	# Файл правится руками: мусорное число читается как первый (раздел 15).
	var file := FileAccess.open(Save.PATH, FileAccess.WRITE)
	file.store_string('{"character": 17}')
	file.close()
	assert_eq(Save.load_character(), 0, "сохранённый номер вне диапазона → 0")
	if backup.is_empty():
		DirAccess.open("user://").remove("save.json")
	else:
		file = FileAccess.open(Save.PATH, FileAccess.WRITE)
		file.store_string(backup)
		file.close()
