# Каркас учёта взаимодействий (раздел 13 SPEC): очки по peer_id, журнал,
# топ для карточек «Встреч», сброс при новом заходе в мир. Сами события
# (мобы, кооп, голос) приходят с этапов П3–П6; полный тест раздела 18 — там же.
extends GutTest

const B: Balance = preload("res://gameplay/balance.tres")


func test_scores_accumulate_per_peer() -> void:
	Interactions.reset()
	Interactions.add_points(7, Interactions.KIND_PULL_GOT, B.pts_pull, 12.5)
	Interactions.add_points(7, Interactions.KIND_BEACON_LIT, B.pts_beacon_lit, 40.0)
	Interactions.add_points(9, Interactions.KIND_EMOTE_REPLY, B.pts_emote_reply, 3.0)
	assert_almost_eq(Interactions.score(7), B.pts_pull + B.pts_beacon_lit, 0.001)
	assert_almost_eq(Interactions.score(9), B.pts_emote_reply, 0.001)
	assert_eq(Interactions.score(123), 0.0, "неизвестный пир — 0")


func test_points_match_section13_table() -> void:
	# Таблица раздела 13: очки фиксированы в balance.tres.
	assert_almost_eq(B.pts_pull, 10.0, 0.001)
	assert_almost_eq(B.pts_beacon_lit, 6.0, 0.001)
	assert_almost_eq(B.pts_gate_open, 6.0, 0.001)
	assert_almost_eq(B.pts_boost, 5.0, 0.001)
	assert_almost_eq(B.pts_firefly, 6.0, 0.001)
	assert_almost_eq(B.pts_hand_held, 4.0, 0.001)
	assert_almost_eq(B.pts_campfire, 3.0, 0.001)
	assert_almost_eq(B.pts_emote_reply, 2.0, 0.001)
	assert_almost_eq(B.pts_proximity, 0.05, 0.0001)
	assert_almost_eq(B.pts_voice_heard, 0.3, 0.001)


func test_events_journal_and_reset() -> void:
	Interactions.reset()
	Interactions.add_points(7, Interactions.KIND_FIREFLY, B.pts_firefly, 55.0)
	var events: Array[Dictionary] = Interactions.events()
	assert_eq(events.size(), 1)
	assert_eq(int(events[0]["peer_id"]), 7)
	assert_eq(str(events[0]["kind"]), Interactions.KIND_FIREFLY)
	assert_almost_eq(float(events[0]["time"]), 55.0, 0.001)
	Interactions.reset()
	assert_eq(Interactions.events().size(), 0)
	assert_eq(Interactions.score(7), 0.0)


func test_top_peers_sorted_by_score() -> void:
	Interactions.reset()
	Interactions.add_points(2, Interactions.KIND_HAND_HELD, 4.0, 1.0)
	Interactions.add_points(3, Interactions.KIND_PULL_GAVE, 10.0, 2.0)
	Interactions.add_points(2, Interactions.KIND_CAMPFIRE, 3.0, 30.0)
	var top: Array[int] = Interactions.top_peers(2)
	assert_eq(top.size(), 2)
	assert_eq(top[0], 3, "10 очков выше 7")
	assert_eq(top[1], 2)


func test_firefly_pair_scores_both_killers() -> void:
	# Раздел 13: вместе поймали золотого светлячка — очки каждому из двоих.
	Interactions.reset()
	# Локальный игрок — peer 1, напарник — 7: убили вдвоём.
	EventBus.mob_killed.emit(13, [1, 7], 500.0)
	assert_almost_eq(Interactions.score(7), B.pts_firefly, 0.001)
	# Чужая пара без меня очков не даёт.
	EventBus.mob_killed.emit(14, [8, 9], 600.0)
	assert_almost_eq(Interactions.score(9), 0.0, 0.001)
	# Одинокий убийца (птица) — тоже не «вместе».
	EventBus.mob_killed.emit(15, [1], 700.0)
	assert_almost_eq(Interactions.score(1), 0.0, 0.001)


func test_boost_scores_both_sides() -> void:
	# Раздел 13: base подсадил jumper — «он подсадил меня» прыгнувшему,
	# «я подсадил его» базе.
	Interactions.reset()
	EventBus.player_boosted.emit(7, 1)  # я (1) спрыгнул с головы 7-го
	assert_almost_eq(Interactions.score(7), B.pts_boost, 0.001)
	EventBus.player_boosted.emit(1, 5)  # пятый спрыгнул с моей головы
	assert_almost_eq(Interactions.score(5), B.pts_boost, 0.001)
	assert_almost_eq(Interactions.score(4), 0.0, 0.001)


func test_beacon_pair_scores_both_lighters() -> void:
	# Раздел 13: вместе зажгли маяк — очки каждому из пары; соло-зажигание
	# (запасной путь) и чужие пары очков не дают.
	Interactions.reset()
	EventBus.beacons_state.emit([0, 1], [1, 7], -1.0)  # мы с 7-м зажгли
	assert_almost_eq(Interactions.score(7), B.pts_beacon_lit, 0.001)
	EventBus.beacons_state.emit([2], [7, 9], -1.0)  # чужая пара без меня
	assert_almost_eq(Interactions.score(9), 0.0, 0.001)
	EventBus.beacons_state.emit([3], [1], -1.0)  # я один (соло-путь)
	assert_almost_eq(Interactions.score(1), 0.0, 0.001)
