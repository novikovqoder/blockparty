# Тесты данных жителей (раздел 16, П4.6 → П5.8 часть D): characters.json —
# тексты троих NPC (имя/девиз/описание/«любит») на двух языках, играбельным
# списком файл больше не является; характеристик нет нигде — внешность игрока
# собирает редактор (Save), все игроки бегут и прыгают одинаково.
extends GutTest

const B: Balance = preload("res://gameplay/balance.tres")
const PLAYER_SCENE: PackedScene = preload("res://gameplay/player/player.tscn")
const TEXT_FIELDS: PackedStringArray = ["name", "motto", "description", "loves"]
const LOCALES: PackedStringArray = ["ru", "en"]


func test_all_three_have_full_data() -> void:
	assert_eq(CharacterData.count(), 3, "трое жителей")
	for index: int in CharacterData.count():
		var entry := CharacterData.get_character(index)
		for field: String in TEXT_FIELDS:
			var texts: Dictionary = entry.get(field, {})
			for locale: String in LOCALES:
				assert_true(
					texts.has(locale),
					"житель %d: поле %s есть на %s" % [index, field, locale]
				)
				assert_false(
					String(texts.get(locale, "")).strip_edges().is_empty(),
					"житель %d: поле %s на %s не пустое" % [index, field, locale]
				)


func test_no_stats_left_in_data() -> void:
	# Характеристики убраны (П5.8, часть D): в characters.json их нет.
	var text := FileAccess.get_file_as_string(CharacterData.PATH)
	assert_false(text.is_empty(), "characters.json читается")
	for key: String in ["stats", "strength", "speed", "jump"]:
		assert_false(
			text.contains('"%s"' % key),
			"characters.json без поля «%s»" % key
		)


func test_out_of_range_falls_back_to_first() -> void:
	# Правило жителей (бывший CharacterModel): номер вне диапазона — первая
	# запись.
	for bad: int in [-7, 99]:
		var entry := CharacterData.get_character(bad)
		var first := CharacterData.get_character(0)
		assert_eq(
			CharacterData.pick_text(entry["name"]),
			CharacterData.pick_text(first["name"]),
			"номер %d: имя от первого жителя" % bad
		)


# --- Все игроки равны: реальная физика CharacterBody3D без множителей ---

func _player_on_floor() -> Player:
	# Своя площадка каждому: игроки не сталкиваются между собой.
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
	return player


func _settle() -> void:
	for i: int in range(3):
		await get_tree().physics_frame


func test_all_players_run_same_speed() -> void:
	# Двое без всяких настроек бегут с одинаковой скоростью B.run_speed —
	# множителей персонажей больше нет («за руку» и соло — одна скорость).
	var first := _player_on_floor()
	var second := _player_on_floor()
	await _settle()
	Input.action_press("move_forward")
	var first_speed := 0.0
	var second_speed := 0.0
	for i: int in range(60):
		await get_tree().physics_frame
		first_speed = maxf(
			first_speed, Vector2(first.velocity.x, first.velocity.z).length()
		)
		second_speed = maxf(
			second_speed, Vector2(second.velocity.x, second.velocity.z).length()
		)
	Input.action_release("move_forward")
	assert_almost_eq(first_speed, B.run_speed, 0.05, "первый: бег B.run_speed")
	assert_almost_eq(second_speed, B.run_speed, 0.05, "второй: та же скорость")


func test_all_players_jump_same_height() -> void:
	# Прыжок без множителя высоты: двое поднимаются одинаково, высота —
	# в пределах раздела 18 (1.3–1.5 м, «на один блок да, на два нет»);
	# точные формулы прыжка проверяет test_player_physics.
	var first := _player_on_floor()
	var second := _player_on_floor()
	await _settle()
	var first_start := first.global_position.y
	var second_start := second.global_position.y
	Input.action_press("jump")
	var first_top := 0.0
	var second_top := 0.0
	for i: int in range(150):
		await get_tree().physics_frame
		first_top = maxf(first_top, first.global_position.y)
		second_top = maxf(second_top, second.global_position.y)
	Input.action_release("jump")
	assert_almost_eq(
		first_top - first_start, second_top - second_start, 0.01,
		"апексы равны — множителей нет",
	)
	assert_between(
		first_top - first_start, 1.3, 1.5, "высота в норме раздела 18"
	)


func test_save_roundtrip_and_invalid_becomes_default() -> void:
	# Тест правит user://save.json — прежнее содержимое восстанавливается.
	var backup := ""
	if FileAccess.file_exists(Save.PATH):
		backup = FileAccess.get_file_as_string(Save.PATH)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261012
	var ap := Appearance.random(rng)
	Save.save_appearance(ap)
	assert_true(Save.load_appearance().same(ap.validated()),
		"сохранённая внешность читается обратно")
	# Бороде не место на женском теле: сохранение чинит комбинацию.
	ap.gender = Appearance.GENDER_FEMALE
	ap.hair = 5
	Save.save_appearance(ap)
	assert_ne(Save.load_appearance().hair, 5, "борода не сохранилась на женское тело")
	# Файл правится руками: мусор в поле — дефолтная внешность.
	var file := FileAccess.open(Save.PATH, FileAccess.WRITE)
	file.store_string('{"appearance": "junk"}')
	file.close()
	assert_true(Save.load_appearance().same(Appearance.default_for(0)),
		"мусор в поле внешности → дефолт")
	if backup.is_empty():
		DirAccess.open("user://").remove("save.json")
	else:
		file = FileAccess.open(Save.PATH, FileAccess.WRITE)
		file.store_string(backup)
		file.close()
