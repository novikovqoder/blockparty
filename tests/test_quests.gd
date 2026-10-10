# Тесты заданий жителей (П5.5): UI-трекер и карта (раздел 15), далее —
# машина состояний, детерминизм раскладки и соло-прохождение (раздел 7
# ТЗ П5.5 — дополняется по ходу этапа).
extends GutTest


## Квартет состояния задания (как в QuestAuthority.state()).
func _quest(stage: int, steps: Array, done_day: int = -1) -> Dictionary:
	return {
		"stage": stage,
		"done_day": done_day,
		"steps": steps,
		"peers": [],
	}


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
