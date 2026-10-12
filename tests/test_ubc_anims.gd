# Тесты анимаций UAL на риге UBC (П5.8, часть C): библиотека anims_ubc.res
# имеет клип для каждого состояния Protocol.AnimState (включая эмоции
# колеса), у обоих полов каждый трек каждого клипа резолвится в кость
# скелета, циклические состояния играются зацикленными клипами; модель
# переключает клипы по set_state, разовый play_one_shot возвращается к
# состоянию, пересборка внешности не роняет аниматор.
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
	# Переключение состояния меняет играющий клип у обоих тел.
	for gender: int in Appearance.GENDERS:
		var model := _make(gender)
		assert_eq(model._playing_clip(), &"Idle",
			"пол %d: после сборки — покой" % gender)
		for state: int in [Protocol.AnimState.WALK, Protocol.AnimState.RUN,
				Protocol.AnimState.SIT, Protocol.AnimState.HANG]:
			model.set_state(state)
			assert_eq(model._playing_clip(),
				CharacterAnims.clip_for_state(state),
				"пол %d: состояние %d играет свой клип" % [gender, state])


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
