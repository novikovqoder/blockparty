# Тест учёта взаимодействий (autoload/interactions.gd, раздел 11): очки по
# игрокам, журнал событий, топ для карточек и сброс между забегами.
# Этап 3 наполняет счёт событиями помощи (вытягивание, ворота, золотая).
extends GutTest


func before_each() -> void:
	Interactions.reset()


func test_add_points_accumulates_per_peer() -> void:
	Interactions.add_points(2, Interactions.KIND_PULL_GAVE, 10.0, 5.0)
	Interactions.add_points(2, Interactions.KIND_GATE_OPEN, 6.0, 20.0)
	Interactions.add_points(3, Interactions.KIND_HEAD_JUMP, 4.0, 30.0)
	assert_almost_eq(Interactions.score(2), 16.0, 0.0001)
	assert_almost_eq(Interactions.score(3), 4.0, 0.0001)
	assert_almost_eq(Interactions.score(4), 0.0, 0.0001, "незнакомец — 0")


func test_events_journal_keeps_order_and_fields() -> void:
	Interactions.add_points(2, Interactions.KIND_PULL_GOT, 10.0, 5.5)
	Interactions.add_points(3, Interactions.KIND_GOLDEN_KILL, 6.0, 40.0)
	var events := Interactions.events()
	assert_eq(events.size(), 2)
	assert_eq(events[0]["peer_id"], 2)
	assert_eq(events[0]["kind"], Interactions.KIND_PULL_GOT)
	assert_almost_eq(events[0]["points"], 10.0, 0.0001)
	assert_almost_eq(events[0]["time"], 5.5, 0.0001)
	assert_eq(events[1]["peer_id"], 3)


func test_top_peers_sorted_by_score() -> void:
	Interactions.add_points(5, Interactions.KIND_PULL_GAVE, 10.0, 1.0)
	Interactions.add_points(2, Interactions.KIND_GATE_OPEN, 6.0, 2.0)
	Interactions.add_points(5, Interactions.KIND_HEAD_JUMP, 4.0, 3.0)
	assert_eq(Interactions.top_peers(3), [5, 2])
	assert_eq(Interactions.top_peers(1), [5])


func test_reset_clears_everything() -> void:
	Interactions.add_points(2, Interactions.KIND_PULL_GAVE, 10.0, 1.0)
	Interactions.reset()
	assert_almost_eq(Interactions.score(2), 0.0, 0.0001)
	assert_eq(Interactions.events().size(), 0)
	assert_eq(Interactions.top_peers(3), [])
