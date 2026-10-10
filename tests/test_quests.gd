# Тесты заданий жителей (П5.5): раздел 7 ТЗ П5.5 — машина состояний
# каждого задания (доступно → идёт → выполнено → доступно на следующий
# день), детерминизм мяты и вех от seed и принадлежность зонам, соло-
# прохождение без сети, прогресс в world_state для опоздавшего, награда
# каждому участнику и только участникам, скрытие жителя при совпадении
# персонажа. Плюс UI-трекер и карта (раздел 15).
extends GutTest

const B: Balance = preload("res://gameplay/balance.tres")
const EPS: float = 0.001


## Запечённый арт острова (карта высот и коллайдеры — как у QuestSystem).
func _art() -> IslandArt:
	return load("res://gameplay/world/island_art.res") as IslandArt


## Квартет состояния задания (как в QuestAuthority.state()).
func _quest(stage: int, steps: Array, done_day: int = -1) -> Dictionary:
	return {
		"stage": stage,
		"done_day": done_day,
		"steps": steps,
		"peers": [],
	}


## Число шагов задания по ТЗ (5 пучков мяты, 3 маяка, 4 вехи).
func _step_total(id: String) -> int:
	match id:
		Protocol.QUEST_THYME:
			return QuestAuthority.THYME_STEPS
		Protocol.QUEST_LUMI:
			return QuestAuthority.LUMI_STEPS
		Protocol.QUEST_FINN:
			return QuestAuthority.FINN_STEPS
		_:
			return 0


func _tracker_labels(tracker: QuestTracker) -> Array:
	var labels: Array = tracker.get("_labels")
	return labels


# --- HUD-трекер (раздел 15) ---


func test_tracker_shows_active_progress() -> void:
	var tracker := QuestTracker.new()
	add_child_autofree(tracker)
	EventBus.quest_state.emit({
		Protocol.QUEST_THYME: _quest(QuestAuthority.ACTIVE, [1, 1, 1, 0, 0]),
		Protocol.QUEST_LUMI: _quest(QuestAuthority.DONE, [1, 1, 1]),
		Protocol.QUEST_FINN: _quest(QuestAuthority.AVAILABLE, [0, 0, 0, 0]),
	})
	var labels := _tracker_labels(tracker)
	assert_true((labels[0] as Label).visible, "идущее задание занимает строку")
	assert_eq(
		(labels[0] as Label).text,
		"%s: %d/%d" % [tr("QUEST_TRACK_MINT"), 3, 5],
		"формат «Мята: 3/5»"
	)
	assert_false((labels[1] as Label).visible, "выполненное задание не в трекере")
	assert_false((labels[2] as Label).visible, "невзятое задание не в трекере")


func test_tracker_orders_by_protocol_and_clears() -> void:
	var tracker := QuestTracker.new()
	add_child_autofree(tracker)
	EventBus.quest_state.emit({
		Protocol.QUEST_FINN: _quest(QuestAuthority.ACTIVE, [1, 1, 1, 1]),
		Protocol.QUEST_LUMI: _quest(QuestAuthority.ACTIVE, [1, 0, 0]),
		Protocol.QUEST_THYME: _quest(QuestAuthority.ACTIVE, [0, 0, 0, 0, 0]),
	})
	var labels := _tracker_labels(tracker)
	assert_eq((labels[0] as Label).text, "%s: %d/%d" % [tr("QUEST_TRACK_MINT"), 0, 5])
	assert_eq((labels[1] as Label).text, "%s: %d/%d" % [tr("QUEST_TRACK_BEACONS"), 1, 3])
	assert_eq((labels[2] as Label).text, "%s: %d/%d" % [tr("QUEST_TRACK_FLAGS"), 4, 4])
	# Все выполнены — трекер пуст.
	EventBus.quest_state.emit({
		Protocol.QUEST_THYME: _quest(QuestAuthority.DONE, [1, 1, 1, 1, 1]),
		Protocol.QUEST_LUMI: _quest(QuestAuthority.DONE, [1, 1, 1], 0),
		Protocol.QUEST_FINN: _quest(QuestAuthority.DONE, [1, 1, 1, 1], 0),
	})
	for i: int in labels.size():
		assert_false((labels[i] as Label).visible, "строка %d скрыта" % i)


# --- Карта (M): точки целей активных заданий ---


func _map_quest_marks(map: IslandMap) -> Array:
	var layer: Control = map.get("_quest_layer")
	var alive: Array = []
	for child: Node in layer.get_children():
		if not child.is_queued_for_deletion():
			alive.append(child)
	return alive


func test_map_marks_undone_steps_only() -> void:
	var map := IslandMap.new()
	add_child_autofree(map)
	var holder := Node3D.new()
	add_child_autofree(holder)
	for i: int in 4:
		var flag := TrailFlag.new()
		flag.index = i
		flag.position = Vector3(10.0 * i, 0.0, 5.0)
		holder.add_child(flag)
	EventBus.quest_state.emit({
		Protocol.QUEST_FINN: _quest(QuestAuthority.ACTIVE, [1, 0, 0, 0]),
	})
	assert_eq(_map_quest_marks(map).size(), 3, "точки только у несделанных вех")
	# Задание завершено — точек нет.
	EventBus.quest_state.emit({
		Protocol.QUEST_FINN: _quest(QuestAuthority.DONE, [1, 1, 1, 1], 0),
	})
	assert_eq(_map_quest_marks(map).size(), 0, "у выполненного задания целей нет")


func test_map_ignores_foreign_nodes_in_group() -> void:
	# Узел чужого класса в группе (страховка фильтра): точки не ломаются
	# и не считают лишнего.
	var map := IslandMap.new()
	add_child_autofree(map)
	var holder := Node3D.new()
	add_child_autofree(holder)
	var flag := TrailFlag.new()
	flag.index = 0
	holder.add_child(flag)
	var stranger := Node3D.new()
	stranger.add_to_group(TrailFlag.FLAG_GROUP)
	holder.add_child(stranger)
	EventBus.quest_state.emit({
		Protocol.QUEST_FINN: _quest(QuestAuthority.ACTIVE, [0, 0, 0, 0]),
	})
	assert_eq(_map_quest_marks(map).size(), 1, "чужой узел группы не даёт точку")

# --- Машина состояний (раздел 7 ТЗ) ---


## Доступно → идёт → выполнено → доступно на следующий день, для каждого
## из трёх заданий; негативные ветки (взять занятое, повторить шаг,
## финал без шагов, пир 0).
func test_state_machine_per_quest() -> void:
	for id: String in Protocol.QUEST_IDS:
		var qa := QuestAuthority.new()
		var total := _step_total(id)
		assert_eq(int((qa.state()[id]["steps"] as Array).size()), total,
			"%s: шагов по ТЗ" % id)
		assert_eq(qa.stage(id), QuestAuthority.AVAILABLE, "%s: доступно" % id)
		assert_false(qa.do_step(id, 0, 7), "%s: шаг недоступного не принят" % id)
		assert_true(qa.take(id, 7, 5), "%s: первый игрок взял" % id)
		assert_false(qa.take(id, 8, 5), "%s: идущее не берётся повторно" % id)
		assert_true(qa.is_active(id), "%s: идёт" % id)
		assert_false(qa.take(id, 0, 5), "%s: пир 0 не может взять" % id)
		for i: int in total:
			assert_true(qa.do_step(id, i, 7), "%s: шаг %d" % [id, i])
			assert_false(qa.do_step(id, i, 9), "%s: повтор шага %d" % [id, i])
		assert_true(qa.steps_done(id), "%s: все шаги сделаны" % id)
		var event := qa.finish(id, 5, [])
		assert_eq((event["peers"] as Array), [7], "%s: взявший — участник" % id)
		assert_eq(int(event["day"]), 5)
		assert_eq(qa.stage(id), QuestAuthority.DONE, "%s: выполнено" % id)
		assert_true(qa.done_today(id, 5), "%s: выполнено сегодня" % id)
		assert_false(qa.done_today(id, 6), "%s: завтра льготы нет" % id)
		assert_false(qa.take(id, 9, 5), "%s: выполненное сегодня не берётся" % id)
		assert_true(qa.day_rollover(6), "%s: смена дня открыла задание" % id)
		assert_eq(qa.stage(id), QuestAuthority.AVAILABLE,
			"%s: снова доступно на следующий день" % id)
		assert_eq(qa.step_progress(id), Vector2i(0, total),
			"%s: шаги сброшены к новому дню" % id)
		assert_true(qa.take(id, 9, 6), "%s: другой игрок берёт заново" % id)


## Взятие в новый день работает и без тика day_rollover (ленивый rollover):
## выполненное вчера открывается само.
func test_take_next_day_lazy_rollover() -> void:
	var qa := QuestAuthority.new()
	assert_true(qa.take(Protocol.QUEST_LUMI, 3, 2))
	for i: int in QuestAuthority.LUMI_STEPS:
		assert_true(qa.do_step(Protocol.QUEST_LUMI, i, 3))
	assert_false((qa.finish(Protocol.QUEST_LUMI, 2, [4]) as Dictionary).is_empty())
	assert_true(qa.take(Protocol.QUEST_LUMI, 5, 3), "день сменился — открылось лениво")
	assert_eq(qa.step_progress(Protocol.QUEST_LUMI), Vector2i(0, 3), "шаги обнулены")


## Финал с неполными шагами не проходит.
func test_finish_requires_all_steps() -> void:
	var qa := QuestAuthority.new()
	assert_true(qa.take(Protocol.QUEST_FINN, 2, 0))
	assert_true(qa.do_step(Protocol.QUEST_FINN, 0, 2))
	assert_eq(qa.finish(Protocol.QUEST_FINN, 2, [2]), {}, "3 вехи из 4 — не финал")
	assert_true(qa.is_active(Protocol.QUEST_FINN))


# --- Детерминизм раскладки от seed (раздел 7 ТЗ) ---


## Мята: дважды одинаковые позиции, пять пучков, все в зоне Лес,
## на высоте выше кромки воды и с взаимным разносом.
func test_mint_deterministic_and_in_forest() -> void:
	var art := _art()
	var first := QuestLayout.mint_positions(art)
	var second := QuestLayout.mint_positions(art)
	assert_eq(first.size(), QuestAuthority.THYME_STEPS, "пять пучков")
	assert_eq(first, second, "позиции детерминированы от seed")
	var zone: Dictionary = IslandGen.ZONES[1]
	var center: Vector2 = zone["center"]
	var radius: float = float(zone["radius"])
	for pos: Vector3 in first:
		var flat := Vector2(pos.x, pos.z)
		assert_lt(flat.distance_to(center), radius, "пучок в зоне Лес")
		assert_gt(pos.y, B.quest_mint_min_height - EPS, "пучок не на пляже")
	for i: int in first.size():
		for j: int in range(i + 1, first.size()):
			assert_gt(
				Vector2(first[i].x, first[i].z).distance_to(Vector2(first[j].x, first[j].z)),
				B.quest_mint_spacing - EPS,
				"пучки разнесены",
			)


## Вехи Финна: детерминированы, четыре, на своей высоте рельефа; вторая
## и третья — у мостка через Расщелину, третья сразу за северной кромкой,
## четвёртая — в зоне Руин.
func test_flags_deterministic_on_route() -> void:
	var art := _art()
	var first := QuestLayout.flag_positions(art)
	var second := QuestLayout.flag_positions(art)
	assert_eq(first.size(), QuestAuthority.FINN_STEPS, "четыре вехи")
	assert_eq(first, second, "позиции детерминированы")
	for i: int in first.size():
		var point: Vector2 = QuestLayout.FLAG_POINTS[i]
		var pos: Vector3 = first[i]
		assert_almost_eq(pos.x, point.x, EPS, "веха %d на маршруте (x)" % (i + 1))
		assert_almost_eq(pos.z, point.y, EPS, "веха %d на маршруте (z)" % (i + 1))
		assert_almost_eq(
			pos.y, QuestLayout.ground_height(art, pos.x, pos.z), EPS,
			"веха %d на высоте рельефа" % (i + 1)
		)
	var bridge_x := float(IslandGen.BRIDGE_X[0])
	for i: int in [1, 2]:
		assert_lt(
			absf(first[i].x - bridge_x), 1.5,
			"веха %d у мостка через Расщелину" % (i + 1)
		)
	assert_gt(first[2].z, float(IslandGen.CREVASSE_Z1),
		"третья веха за северной кромкой Расщелины")
	assert_lt(first[2].z, float(IslandGen.CREVASSE_Z1) + 8.0,
		"третья веха сразу за кромкой")
	var ruins: Dictionary = IslandGen.ZONES[2]
	var ruins_center: Vector2 = ruins["center"]
	assert_lt(
		Vector2(first[3].x, first[3].z).distance_to(ruins_center),
		float(ruins["radius"]), "четвёртая веха в зоне Руин"
	)


## Жители: три места, у каждого своё задание, Тимьян сидит у костра,
## стоящие — на краю Площади лицом к центру.
func test_npc_spots_deterministic() -> void:
	var art := _art()
	var first := QuestLayout.npc_spots(art)
	var second := QuestLayout.npc_spots(art)
	assert_eq(first.size(), Protocol.QUEST_IDS.size(), "трое жителей")
	assert_eq(first, second, "места детерминированы")
	var plaza: Dictionary = IslandGen.ZONES[0]
	var plaza_center: Vector2 = plaza["center"]
	var seen_ids: Array = []
	for spot: Dictionary in first:
		seen_ids.append(String(spot["quest_id"]))
		var pos: Vector3 = spot["pos"]
		if bool(spot["sitting"]):
			assert_eq(int(spot["character"]), 2, "сидит Тимьян")
			assert_lt(
				Vector2(pos.x, pos.z).distance_to(Vector2(
					QuestLayout.CAMPFIRE.x, QuestLayout.CAMPFIRE.z)),
				3.0, "Тимьян у костра"
			)
		else:
			assert_almost_eq(
				Vector2(pos.x, pos.z).distance_to(plaza_center),
				QuestLayout.PLAZA_EDGE, EPS, "стоящий на краю Площади"
			)
	for id: String in Protocol.QUEST_IDS:
		assert_true(seen_ids.has(id), "у жителя есть задание %s" % id)


# --- Соло-прохождение (раздел 7 ТЗ: симуляция без сети) ---


## Каждое задание проходится одним игроком: взял, сделал все шаги,
## финал — и награда уходит этому же игроку.
func test_each_quest_solo_completable() -> void:
	for id: String in Protocol.QUEST_IDS:
		var qa := QuestAuthority.new()
		assert_true(qa.take(id, 7, 1), "%s: взял" % id)
		for i: int in _step_total(id):
			assert_true(qa.do_step(id, i, 7), "%s: шаг %d тем же игроком" % [id, i])
		var event := qa.finish(id, 1, [7])
		assert_eq((event["peers"] as Array), [7],
			"%s: соло-прохождение награждает одного" % id)
		assert_true(qa.done_today(id, 1))


## Бонус Тимьяна: 10 каждому, +2 за каждого ДРУГОГО сидящего, до +10.
func test_thyme_reward_bonus() -> void:
	assert_eq(QuestAuthority.thyme_reward(0, B), B.quest_reward_base, "соло — база")
	assert_eq(
		QuestAuthority.thyme_reward(1, B),
		B.quest_reward_base + B.quest_thyme_bonus_per_other, "+2 за одного"
	)
	assert_eq(
		QuestAuthority.thyme_reward(5, B),
		B.quest_reward_base + B.quest_thyme_bonus_max, "потолок бонуса +10"
	)
	assert_eq(
		QuestAuthority.thyme_reward(100, B),
		B.quest_reward_base + B.quest_thyme_bonus_max, "выше потолка не даёт"
	)


# --- world_state: прогресс доходит опоздавшему (раздел 7 ТЗ) ---


## Состояние заданий сериализуется в world_state без потерь.
func test_quest_state_survives_world_state_pack() -> void:
	var qa := QuestAuthority.new()
	assert_true(qa.take(Protocol.QUEST_THYME, 3, 4))
	qa.do_step(Protocol.QUEST_THYME, 0, 3)
	qa.do_step(Protocol.QUEST_THYME, 1, 5)
	qa.do_step(Protocol.QUEST_THYME, 2, 3)
	var state := {
		"world_epoch_msec": 1000,
		"world_time_offset_sec": 0.0,
		"players": [],
		"dead_mobs": [],
		"taken_coins": [],
		"activities": {"quests": qa.state()},
	}
	var parsed: Dictionary = WorldState.unpack(WorldState.pack(state))
	var quests: Dictionary = (parsed["activities"] as Dictionary)["quests"]
	assert_eq(
		quests[Protocol.QUEST_THYME]["steps"], [1, 1, 1, 0, 0],
		"прогресс шагов прошёл пакет"
	)
	assert_eq(int(quests[Protocol.QUEST_THYME]["stage"]), QuestAuthority.ACTIVE)
	assert_eq(quests[Protocol.QUEST_THYME]["peers"], [3, 5], "участники прошли")


## Опоздавший применяет world_state и получает тот же прогресс задания
## (тот же канал, что у подключившегося позже: _apply_activities).
func test_late_joiner_gets_same_progress() -> void:
	var received: Array = []
	var callback := func(state: Dictionary) -> void: received.append(state)
	EventBus.quest_state.connect(callback)
	var qa := QuestAuthority.new()
	assert_true(qa.take(Protocol.QUEST_LUMI, 3, 4))
	qa.do_step(Protocol.QUEST_LUMI, 0, 3)
	Net._apply_activities({"activities": {"quests": qa.state()}})
	EventBus.quest_state.disconnect(callback)
	assert_eq(received.size(), 1, "событие пришло один раз")
	var quest: Dictionary = received[0][Protocol.QUEST_LUMI]
	assert_eq(int(quest["stage"]), QuestAuthority.ACTIVE, "задание идёт")
	assert_eq(quest["steps"], [1, 0, 0], "тот же прогресс шагов")


# --- Награда каждому участнику и только участникам (раздел 7 ТЗ) ---


## Участники — взявший, делавшие шаги и все в радиусе финала; остальные
## награду не получают.
func test_reward_participants_only() -> void:
	var qa := QuestAuthority.new()
	assert_true(qa.take(Protocol.QUEST_FINN, 7, 2))
	assert_true(qa.do_step(Protocol.QUEST_FINN, 0, 9))
	assert_true(qa.do_step(Protocol.QUEST_FINN, 1, 7))
	assert_true(qa.do_step(Protocol.QUEST_FINN, 2, 9))
	assert_true(qa.do_step(Protocol.QUEST_FINN, 3, 7))
	var event := qa.finish(Protocol.QUEST_FINN, 2, [7, 11, 13])
	var peers: Array = event["peers"]
	for expected: int in [7, 9, 11, 13]:
		assert_true(peers.has(expected), "участник %d награждён" % expected)
	assert_eq(peers.size(), 4, "дубликат из радиуса финала не удваивает список")
	assert_false(peers.has(21), "стоявший в стороне не награждён")


## Начисление монет на клиенте: каждому участнику по списку peers, чужие
## ничего не получают (тот же метод, что рассылает хост).
func test_reward_coins_local_participant_only() -> void:
	var saved_peer: int = Net.local_peer_id
	var saved_coins: int = Session.world_coins
	Net.local_peer_id = 11
	Net.rpc_quest_reward(Protocol.QUEST_LUMI, [7, 11], [10, 10], {})
	assert_eq(Session.world_coins, saved_coins + 10, "участник получил монеты")
	Net.rpc_quest_reward(Protocol.QUEST_LUMI, [7], [10], {})
	assert_eq(Session.world_coins, saved_coins + 10, "неучастник не получил")
	Net.rpc_quest_reward(Protocol.QUEST_LUMI, [11], [10], {})
	assert_eq(Session.world_coins, saved_coins + 20, "ещё одна награда — ещё монеты")
	Net.local_peer_id = saved_peer
	Session.world_coins = saved_coins


# --- Скрытие жителя при совпадении персонажа (раздел 7 ТЗ) ---


## Локальный игрок играет тем же персонажем — житель скрыт, на его месте
## табличка «Записка от …»; другим персонажем — житель виден.
func test_townsfolk_hidden_for_same_character() -> void:
	var backup: String = ""
	if FileAccess.file_exists(Save.PATH):
		backup = FileAccess.get_file_as_string(Save.PATH)
	Save.save_character(1)
	var folk_same := Townsfolk.new()
	folk_same.character = 1
	folk_same.quest_id = Protocol.QUEST_LUMI
	add_child_autofree(folk_same)
	var folk_other := Townsfolk.new()
	folk_other.character = 0
	folk_other.quest_id = Protocol.QUEST_FINN
	add_child_autofree(folk_other)
	assert_true(bool(folk_same.get("_hidden")), "житель-двойник скрыт")
	assert_false((folk_same.get_node("Model") as Node3D).visible, "модель скрыта")
	assert_true((folk_same.get_node("Note") as Node3D).visible, "табличка видна")
	assert_false((folk_same.get_node("Badge") as Label3D).visible, "значка нет")
	assert_false(bool(folk_other.get("_hidden")), "другой персонаж не скрывает")
	assert_true((folk_other.get_node("Model") as Node3D).visible, "модель видна")
	assert_false((folk_other.get_node("Note") as Node3D).visible, "таблички нет")
	var file := FileAccess.open(Save.PATH, FileAccess.WRITE)
	if backup.is_empty():
		file.store_string("{}")
	else:
		file.store_string(backup)
	file.close()


# --- Физическая форма жителя (баг vfx-fix: сквозь NPC проходили) ---


## У жителя есть StaticBody3D с капсулой по габариту модели: нижняя точка
## у ступней (модели стоят «ногами» в origin), верх — на уровне макушки.
func test_townsfolk_has_capsule_collision() -> void:
	var folk := Townsfolk.new()
	folk.character = 2
	folk.quest_id = Protocol.QUEST_THYME
	folk.sitting = true
	add_child_autofree(folk)
	var bodies: Array = folk.find_children("Body", "StaticBody3D", false, false)
	assert_eq(bodies.size(), 1, "у жителя один StaticBody3D")
	var shape := (bodies[0] as StaticBody3D).get_child(0) as CollisionShape3D
	assert_not_null(shape.shape, "форма коллизии задана")
	var capsule := shape.shape as CapsuleShape3D
	assert_ne(capsule, null, "форма — капсула")
	assert_almost_eq(
		shape.position.y - capsule.height * 0.5, 0.0, EPS,
		"нижняя точка капсулы у ступней",
	)
	assert_almost_eq(
		shape.position.y + capsule.height * 0.5,
		CharacterModel.HEAD_TOP_Y, EPS, "верх капсулы на уровне макушки",
	)
	# Слой 1 — маска игрока (collision_mask = 1): капсула реально блокирует.
	var body := bodies[0] as StaticBody3D
	assert_true(body.get_collision_layer_value(1), "тело жителя на слое 1 (мир)")
	assert_almost_eq(capsule.radius, folk.COLLISION_RADIUS, EPS, "радиус капсулы")
