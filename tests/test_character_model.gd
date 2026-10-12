# Тесты модели персонажа (П5.7, блок 4): все три реалистичные модели
# MakeHuman/MPFB строятся, ступни на y = 0 (±0.02), макушка головы (по волосам,
# без шляпы) подогнана под коллизию игрока, у каждого крупного меша есть
# облегчённая копия _LOD с раскладкой по дистанции видимости, чёрного
# мультяшного контура нет, фирменные детали запечены в модели (Detail_*);
# цвет игрока тонирует только материал PlayerColor верхней одежды; цветовой
# индекс по хэшу id детерминирован, все 6 цветов достижимы, номер вне
# диапазона даёт 0.
extends GutTest

const MODEL: PackedScene = preload("res://gameplay/player/character_model.tscn")
## Риг MPFB game_engine (tools/make_characters.py): 53 кости (Root + 52).
const BONES_MPFB: int = 53


func _make(character: int) -> CharacterModel:
	var model := MODEL.instantiate() as CharacterModel
	add_child_autofree(model)
	model.setup(character)
	return model


func test_all_three_characters_build() -> void:
	for character: int in CharacterModel.count():
		var model := _make(character)
		assert_eq(model.character, character, "персонаж %d: номер зафиксирован" % character)
		var skeleton := model.find_children("*", "Skeleton3D", true, false)
		assert_eq(skeleton.size(), 1, "персонаж %d: один скелет" % character)
		assert_eq(
			(skeleton[0] as Skeleton3D).get_bone_count(), BONES_MPFB,
			"персонаж %d: риг MPFB game_engine" % character,
		)


func test_feet_at_zero_and_head_under_collision() -> void:
	# П5.7: точка опоры — у ступней, рост подогнан под коллизию
	# (HEAD_TOP_Y 1.65 у player.tscn и remote_player.gd).
	for character: int in CharacterModel.count():
		var model := _make(character)
		assert_between(
			model.lowest_point(), -0.02, 0.02,
			"персонаж %d: нижняя точка y=0" % character,
		)
		assert_between(
			model.head_top_height(), 1.60, 1.70,
			"персонаж %d: макушка головы ~1.65 (факт %.3f)"
			% [character, model.head_top_height()],
		)


func test_no_cartoon_outline() -> void:
	# Чёрный контур (обратная оболочка KayKit-моделей) в П5.7 убран: ни одного
	# контурного близнеца ни у одного персонажа.
	for character: int in CharacterModel.count():
		var model := _make(character)
		for node in model.find_children("*", "MeshInstance3D", true, false):
			assert_false(
				(node as MeshInstance3D).name.ends_with("Outline"),
				"персонаж %d: узла-контура нет" % character,
			)


func test_lod_twin_for_every_body_mesh() -> void:
	# Каждый крупный меш (тело, одежда, волосы, обувь, шляпа) имеет _LOD-копию
	# из того же glb; декоративные мелочи (Detail_*) копий не имеют — видны
	# на любой дистанции.
	for character: int in CharacterModel.count():
		var model := _make(character)
		assert_gt(model.lod_pairs(), 5, "персонаж %d: LOD-пар несколько" % character)
		for node in model.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			var is_lod := (mi.name as String).ends_with("_LOD")
			var is_detail := (mi.name as String).begins_with("Detail")
			if is_lod:
				assert_true(
					mi.get_parent().has_node(
						String(mi.name).substr(0, String(mi.name).length() - 4)),
					"персонаж %d: у %s есть полная версия" % [character, mi.name],
				)
				assert_almost_eq(
					mi.visibility_range_begin, model.lod_distance, 0.01,
					"персонаж %d: %s включается с дистанции LOD" % [character, mi.name],
				)
				assert_eq(mi.visibility_range_end, 0.0,
					"персонаж %d: %s виден до бесконечности" % [character, mi.name])
			elif is_detail:
				assert_eq(mi.visibility_range_begin, 0.0,
					"персонаж %d: деталь %s всегда видна" % [character, mi.name])
			else:
				assert_true(
					mi.get_parent().has_node(String(mi.name) + "_LOD"),
					"персонаж %d: у меша %s есть LOD-копия" % [character, mi.name],
				)
				assert_almost_eq(
					mi.visibility_range_end, model.lod_distance, 0.01,
					"персонаж %d: %s гаснет на дистанции LOD" % [character, mi.name],
				)


func test_set_lod_distance_updates_ranges() -> void:
	# Уровни качества (П5.7, блок 7): «Простая» графика приближает переключение.
	var model := _make(0)
	model.set_lod_distance(7.0)
	var checked := 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if (mi.name as String).ends_with("_LOD"):
			assert_almost_eq(mi.visibility_range_begin, 7.0, 0.01,
				"LOD-копия переключилась на 7 м")
			checked += 1
	assert_gt(checked, 5, "проверено несколько LOD-копий")


func test_signature_details_baked_into_models() -> void:
	# Фирменные детали (раздел 16): у Финна ушки на шляпе, у Луми ракушка,
	# у Тимьяна панама с ростком — запечены в glb с префиксом Detail_.
	const EXPECTED: Array = [
		["Detail_ear_l", "Detail_ear_r", "Detail_hat"],
		["Detail_shell", "Detail_hat"],
		["Detail_hat_crown", "Detail_hat_brim", "Detail_sprout_stalk"],
	]
	assert_eq(CharacterModel.count(), EXPECTED.size(), "трое персонажей")
	for character: int in CharacterModel.count():
		var model := _make(character)
		var names: Array[String] = []
		for node in model.find_children("*", "MeshInstance3D", true, false):
			names.append(node.name)
		for wanted: String in EXPECTED[character]:
			assert_has(names, wanted,
				"персонаж %d: деталь %s в модели" % [character, wanted])


func test_palette_index_deterministic_and_complete() -> void:
	# Один id — один цвет (Steam id / peer id, включая отрицательные),
	# все 6 вариантов достижимы (раздел 16, «Цвета»).
	var seen: Array[int] = []
	for id: int in [-7654321, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 11, 7654321]:
		var index := CharacterModel.palette_index(id)
		assert_eq(
			CharacterModel.palette_index(id), index,
			"id %d: цвет не меняется между вызовами" % id,
		)
		assert_between(index, 0, 5, "id %d: индекс в диапазоне" % id)
		seen.push_back(index)
	for expected: int in 6:
		assert_has(seen, expected, "цвет %d достижим каким-то id" % expected)
	# Отрицательный peer id не даёт отрицательного индекса.
	assert_eq(CharacterModel.palette_index(-13), 13 % 6, "absi для peer id")


func test_character_out_of_range_gives_first() -> void:
	assert_eq(CharacterModel.valid_index(-1), 0, "отрицательный → 0")
	assert_eq(CharacterModel.valid_index(99), 0, "за диапазоном → 0")
	assert_eq(CharacterModel.valid_index(1), 1, "валидный проходит как есть")
	var model := _make(42)
	assert_eq(model.character, 0, "setup с неверным номером строит первого")


func test_setup_palette_tints_only_player_color() -> void:
	# П5.7: цвет игрока тонирует только заметную часть одежды (материал
	# PlayerColor: поло/свитер/футболка) в полной версии и в LOD-копии;
	# кожа, волосы и обувь цвет не получают.
	const PAL: Palette = preload("res://assets/palette.tres")
	for character: int in CharacterModel.count():
		var model := _make(character)
		var id := 7654321
		model.setup_palette(id)
		var expected: Color = PAL.player_colors[CharacterModel.palette_index(id)]
		var tinted := 0
		for node in model.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			for surface: int in mi.mesh.get_surface_count():
				var base := mi.mesh.surface_get_material(surface) as StandardMaterial3D
				var override := mi.get_surface_override_material(surface)
				if base != null and base.resource_name == "PlayerColor":
					tinted += 1
					assert_true(
						override is StandardMaterial3D,
						"персонаж %d: %s surface %d тонирован"
						% [character, mi.name, surface],
					)
					assert_true(
						(override as StandardMaterial3D).albedo_color.is_equal_approx(expected),
						"персонаж %d: %s цвет варианта" % [character, mi.name],
					)
				else:
					assert_null(override,
						"персонаж %d: %s surface %d не тронут цветом"
						% [character, mi.name, surface])
		assert_gt(tinted, 1, "персонаж %d: PlayerColor и в полной, и в LOD" % character)


# --- Анимации (интерфейс состояний; клипы — CharacterAnims) ---

func test_every_anim_state_maps_to_existing_clip() -> void:
	# Каждое состояние аниматора (раздел 5) играет назначенный клип — включая
	# состояния без своего клипа в наборе (ближайший по смыслу).
	var lib := CharacterAnims.library()
	for state: int in Protocol.AnimState.values():
		var clip: StringName = CharacterAnims.clip_for_state(state)
		assert_ne(clip, &"", "состояние %d: назначен клип" % state)
		assert_true(
			lib.has_animation(clip),
			"состояние %d: клип %s есть в библиотеке" % [state, clip],
		)
	# Циклические состояния зациклены, разовые — нет.
	for clip: String in ["Idle", "Walk", "Jog_Fwd", "NinjaJump_Idle",
			"Sitting_Idle", "Hang_Pose", "Walk_Hand"]:
		assert_eq(
			(lib.get_animation(clip) as Animation).loop_mode, Animation.LOOP_LINEAR,
			"клип %s зациклен" % clip,
		)
	assert_ne(
		(lib.get_animation("Wave_Hand") as Animation).loop_mode, Animation.LOOP_LINEAR,
		"взмах — разовый клип",
	)
	assert_true(CharacterAnims.is_loop(Protocol.AnimState.IDLE), "покой цикличен")
	assert_false(CharacterAnims.is_loop(Protocol.AnimState.WAVE), "взмах разовый")


func test_set_state_plays_matching_clip() -> void:
	# Покой/ходьба/бег/фазы прыжка/сесть — свой клип; переходы через blend
	# не мешают сразу читать current_animation.
	var model := _make(0)
	var player := _anim_player(model)
	var cases := {
		Protocol.AnimState.IDLE: "mpfb/Idle",
		Protocol.AnimState.WALK: "mpfb/Walk",
		Protocol.AnimState.RUN: "mpfb/Jog_Fwd",
		Protocol.AnimState.JUMP: "mpfb/Jump_Start",
		Protocol.AnimState.FALL: "mpfb/NinjaJump_Idle",
		Protocol.AnimState.LAND: "mpfb/Jump_Land",
		Protocol.AnimState.SIT: "mpfb/Sitting_Idle",
		Protocol.AnimState.WAVE: "mpfb/Wave_Hand",
	}
	for state: int in cases.keys():
		model.set_state(state)
		assert_eq(
			player.current_animation, cases[state],
			"состояние %d играет %s" % [state, cases[state]],
		)
	# Тот же клип не перезапускается (взмах не сбивается кадром «всё ещё
	# бег»): позиция не сбрасывается в начало ни set_state, ни play_one_shot.
	model.set_state(Protocol.AnimState.WAVE)
	player.seek(1.0)
	model.set_state(Protocol.AnimState.WAVE)
	assert_almost_eq(
		player.current_animation_position, 1.0, 0.02,
		"повторный set_state не перезапускает клип",
	)
	model.play_one_shot(Protocol.AnimState.WAVE, 2.0)
	assert_almost_eq(
		player.current_animation_position, 1.0, 0.02,
		"play_one_shot поверх того же клипа продолжает его",
	)


func test_play_one_shot_speeds_up_and_returns() -> void:
	# Разовая анимация подгоняется под длительность и возвращает состояние.
	var model := _make(1)
	var player := _anim_player(model)
	model.set_state(Protocol.AnimState.SIT)
	model.play_one_shot(Protocol.AnimState.WAVE, 0.3)
	assert_eq(player.current_animation, "mpfb/Wave_Hand", "играет взмах")
	assert_gt(player.speed_scale, 1.0, "короткий вызов ускоряет клип")
	# Фактическая длительность взмаха при клампе скорости ~0.85 с.
	await get_tree().create_timer(1.2).timeout
	assert_eq(player.current_animation, "mpfb/Sitting_Idle", "вернулись к состоянию")
	assert_eq(player.speed_scale, 1.0, "скорость восстановлена")


func test_animations_attach_on_all_characters() -> void:
	# Плеер один, лежит в корне glb, клипы назначаются на всех персонажах
	# (ретаргетинг на риг MPFB — П5.7, блок 5).
	for character: int in CharacterModel.count():
		var model := _make(character)
		var players := model.find_children("*", "AnimationPlayer", true, false)
		assert_eq(players.size(), 1, "персонаж %d: один AnimationPlayer" % character)
		model.set_state(Protocol.AnimState.RUN)
		assert_eq(
			(players[0] as AnimationPlayer).current_animation, "mpfb/Jog_Fwd",
			"персонаж %d: клип назначен" % character,
		)


func _anim_player(model: CharacterModel) -> AnimationPlayer:
	var players := model.find_children("*", "AnimationPlayer", true, false)
	assert_eq(players.size(), 1, "в модели один AnimationPlayer")
	return players[0] as AnimationPlayer
