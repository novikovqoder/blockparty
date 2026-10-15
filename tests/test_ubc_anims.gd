# Тесты анимаций UAL на риге UBC (П5.8, часть C): библиотека anims_ubc.res
# имеет клип для каждого состояния Protocol.AnimState (включая эмоции
# колеса), у обоих полов каждый трек каждого клипа резолвится в кость
# скелета, циклические состояния играются зацикленными клипами; модель
# переключает клипы по set_state, разовый play_one_shot возвращается к
# состоянию, пересборка внешности не роняет аниматор.
# Возврат П5.8 (T-pose): + проверки, что анимация ДОХОДИТ до мешей —
# позы ключевых костей ходьбы против покоя (численно, с порогом),
# скин-привязка мешей (skeleton-путь резолвится в скелет сцены) и сдвиг
# вершин меша ног за костями (формула скиннинга рендера).
extends GutTest

const MODEL: PackedScene = preload("res://gameplay/player/character_model.tscn")


func _make(gender: int) -> CharacterModel:
	var model := MODEL.instantiate() as CharacterModel
	add_child_autofree(model)
	model.setup_appearance(Appearance.default_for(gender))
	return model


func test_every_state_has_clip() -> void:
	# Полный покров состояний: у каждого Protocol.AnimState есть клип
	# в библиотеке (сетевой формат не меняется, раздел 10 SPEC).
	var lib := CharacterAnims.library()
	for state: int in Protocol.AnimState.values():
		var clip := CharacterAnims.clip_for_state(state)
		assert_ne(clip, &"", "состояние %d: назначен клип" % state)
		assert_true(lib.has_animation(clip),
			"состояние %d: клип %s есть в anims_ubc.res" % [state, clip])


func test_all_tracks_resolve_on_both_bodies() -> void:
	# Треки «Armature/Skeleton3D:<кость>»: узел есть, кость есть — на обоих
	# телах (риг полов общий, но сцены разные).
	var lib := CharacterAnims.library()
	for gender: int in Appearance.GENDERS:
		var model := _make(gender)
		var sk := model.find_children("*", "Skeleton3D", true,
			false)[0] as Skeleton3D
		for clip_name: StringName in lib.get_animation_list():
			var anim := lib.get_animation(clip_name) as Animation
			assert_gt(anim.get_track_count(), 0,
				"пол %d: клип %s не пуст" % [gender, clip_name])
			for i: int in anim.get_track_count():
				var path := anim.track_get_path(i)
				var node := model._root.get_node_or_null(
					NodePath(str(path).get_slice(":", 0)))
				assert_not_null(node, "пол %d: клип %s трек %s — узел"
					% [gender, clip_name, path])
				if node == null:
					continue
				assert_gt(sk.find_bone(str(path).get_slice(":", 1)), -1,
					"пол %d: клип %s трек %s — кость"
					% [gender, clip_name, path])


func test_loop_states_play_looped_clips() -> void:
	# Локомоция/вис/сидение — циклы: клип кончился и начался заново,
	# без провала в T-pose между кадрами.
	var lib := CharacterAnims.library()
	for state: int in CharacterAnims.LOOP_STATES:
		var anim := lib.get_animation(
			CharacterAnims.clip_for_state(state)) as Animation
		assert_ne(anim.loop_mode, Animation.LOOP_NONE,
			"состояние %d: клип зациклен" % state)


func test_set_state_switches_clip() -> void:
	# Переключение состояния меняет играющий клип у обоих тел. Ходьба/бег —
	# локомоция по фактической скорости (Д3), их проверяет отдельный тест.
	for gender: int in Appearance.GENDERS:
		var model := _make(gender)
		assert_eq(model._playing_clip(), &"Idle",
			"пол %d: после сборки — покой" % gender)
		for state: int in [Protocol.AnimState.SIT, Protocol.AnimState.HANG,
				Protocol.AnimState.FALL]:
			model.set_state(state)
			assert_eq(model._playing_clip(),
				CharacterAnims.clip_for_state(state),
				"пол %d: состояние %d играет свой клип" % [gender, state])


func test_locomotion_follows_speed() -> void:
	# Д3: ходьба/бег выбирают клип и каденцию по фактической скорости:
	# медленно — Walk, шаг/лёгкий бег — Jog_Fwd, спринт — Sprint; темп
	# scale = скорость/natural (стопы не скользят). «За руку» — Walk_Hand
	# с темпом по скорости пары.
	var model := _make(0)
	model.set_state(Protocol.AnimState.RUN)
	for pair: Array in [[0.5, &"Walk"], [2.5, &"Jog_Fwd"], [6.0, &"Sprint"]]:
		model.set_locomotion_speed(pair[0])
		for i: int in 90:  # сглаживание ~10/с: за 1.5 с доходит
			model._process(1.0 / 60.0)
		assert_eq(model._playing_clip(), pair[1],
			"скорость %.1f м/с — клип %s" % [pair[0], pair[1]])
		var natural: float = CharacterAnims.natural_speed(pair[1])
		assert_almost_eq(model._player.speed_scale,
			clampf(pair[0] / natural, CharacterAnims.SPEED_SCALE_MIN,
				CharacterAnims.SPEED_SCALE_MAX),
			0.05, "скорость %.1f: темп = скорость/natural" % pair[0])
	model.set_state(Protocol.AnimState.HOLD_HAND)
	model.set_locomotion_speed(1.0)
	for i: int in 90:
		model._process(1.0 / 60.0)
	assert_eq(model._playing_clip(), &"Walk_Hand", "за руку — Walk_Hand")
	assert_almost_eq(model._player.speed_scale, 1.0 / 0.96, 0.05,
		"за руку: темп по скорости пары")


func test_one_shot_returns_to_state() -> void:
	# Взмах поверх ходьбы: играет разовый клип, по таймеру возвращает
	# состояние (сетевое/локальное), взмах не сбивается повторным кадром
	# «всё ещё ходьба».
	var model := _make(0)
	model.set_state(Protocol.AnimState.WALK)
	model.play_one_shot(Protocol.AnimState.WAVE, 0.25)
	assert_eq(model._playing_clip(), &"Wave_Hand", "взмах играет")
	model.set_state(Protocol.AnimState.WALK)
	assert_eq(model._playing_clip(), &"Wave_Hand",
		"кадр состояния не сбивает разовый клип")
	for i: int in 90:
		model._process(1.0 / 60.0)
	assert_eq(model._playing_clip(), &"Walk", "после взмаха — ходьба")


func test_rebuild_keeps_animator() -> void:
	# Смена внешности пересобирает модель: плеер создаётся заново и
	# продолжает играть состояние (редактор внешности, часть B).
	var model := _make(0)
	model.set_state(Protocol.AnimState.SIT)
	var changed := Appearance.default_for(1)
	changed.hair = 0
	model.setup_appearance(changed)
	assert_eq(model._playing_clip(), &"Sitting_Idle",
		"после пересборки играет состояние")


# --- Возврат П5.8 (T-pose): анимация обязана доходит до мешей ---

func test_walk_pose_differs_from_idle() -> void:
	# Поза ходьбы против покоя, оба пола: ключевые кости (бедро, колено,
	# плечо) поворачиваются на заметный угол И вершины меша ног едут за
	# костями (численный скиннинг). До возврата П5.8 кости двигались, а
	# меши стояли в байнд-позе — эти проверки ловят именно такой разрыв.
	for gender: int in Appearance.GENDERS:
		var model := _make(gender)
		var result: Dictionary = await AnimSelfCheck.run(model, true)
		assert_true(result["ok"], "пол %d: %s" % [gender,
			" ; ".join(result["reasons"] as PackedStringArray)])


func test_skin_binds_meshes_to_skeleton() -> void:
	# Регрессия возврата П5.8: у меша со скином skeleton-путь обязан
	# резолвиться в Skeleton3D сцены — пустой путь молча выключает
	# скиннинг на рендере (никаких ошибок в логе, T-pose).
	for gender: int in Appearance.GENDERS:
		var model := _make(gender)
		var skel := model.find_children("*", "Skeleton3D", true,
			false)[0] as Skeleton3D
		var with_skin := 0
		for node in model.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.skin == null:
				continue
			with_skin += 1
			var target := mi.get_node_or_null(mi.skeleton)
			assert_not_null(target, "пол %d: меш %s — skeleton-путь «%s»"
				% [gender, mi.name, String(mi.skeleton)])
			if target is Skeleton3D:
				assert_eq((target as Skeleton3D), skel,
					"пол %d: меш %s ведёт к скелету сцены" % [gender, mi.name])
		assert_gt(with_skin, 20,
			"пол %d: мешей со скином не меньше частей×2 (пол+LOD)" % gender)
