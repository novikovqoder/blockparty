# Каркас учёта взаимодействий (раздел 13 SPEC): очки по peer_id, журнал,
# топ для карточек «Встреч», сброс при новом заходе в мир. Кооп-виды
# Blockparty (подсадка, вытягивание, «за руку», ворота руин) удалены
# с наследием (born-unblessed) — остались близость, голос, костёр.
extends GutTest

const B: Balance = preload("res://gameplay/balance.tres")


func test_scores_accumulate_per_peer() -> void:
	Interactions.reset()
	Interactions.add_points(7, Interactions.KIND_PROXIMITY, B.pts_proximity, 12.5)
	Interactions.add_points(9, Interactions.KIND_VOICE_HEARD, B.pts_voice_heard, 3.0)
	assert_almost_eq(Interactions.score(7), B.pts_proximity, 0.0001)
	assert_almost_eq(Interactions.score(9), B.pts_voice_heard, 0.001)
	assert_eq(Interactions.score(123), 0.0, "неизвестный пир — 0")


func test_points_match_section13_table() -> void:
	# Таблица раздела 13: очки фиксированы в balance.tres.
	assert_almost_eq(B.pts_campfire, 3.0, 0.001)
	assert_almost_eq(B.pts_proximity, 0.05, 0.0001)
	assert_almost_eq(B.pts_voice_heard, 0.3, 0.001)


func test_events_journal_and_reset() -> void:
	Interactions.reset()
	Interactions.add_points(7, Interactions.KIND_CAMPFIRE, B.pts_campfire, 55.0)
	var events: Array[Dictionary] = Interactions.events()
	assert_eq(events.size(), 1)
	assert_eq(int(events[0]["peer_id"]), 7)
	assert_eq(str(events[0]["kind"]), Interactions.KIND_CAMPFIRE)
	assert_almost_eq(float(events[0]["time"]), 55.0, 0.001)
	Interactions.reset()
	assert_eq(Interactions.events().size(), 0)
	assert_eq(Interactions.score(7), 0.0)


func test_top_peers_sorted_by_score() -> void:
	Interactions.reset()
	Interactions.add_points(2, Interactions.KIND_VOICE_HEARD, 4.0, 1.0)
	Interactions.add_points(3, Interactions.KIND_PROXIMITY, 10.0, 2.0)
	Interactions.add_points(2, Interactions.KIND_CAMPFIRE, 3.0, 30.0)
	var top: Array[int] = Interactions.top_peers(2)
	assert_eq(top.size(), 2)
	assert_eq(top[0], 3, "10 очков выше 7")
	assert_eq(top[1], 2)
