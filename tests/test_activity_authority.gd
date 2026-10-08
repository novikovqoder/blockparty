# Обязательные тесты раздела 18 (П5): чистая логика хоста активностей.
# Блок 1 — вытягивание из расщелины (раздел 9.1); блок 2 — ворота руин,
# плиты и сундук (разделы 8, 9.2): N = min(3, игроков) ≥ 2, запасной путь
# одиночки 60 с у ворот, сброс 10 минут; блок 5 — маяки и Звездопад
# (раздел 7): пара в окне 3 с, соло-удержание, цикл гашения, звёзды;
# блок 6 — «за руку» (раздел 9.5): роли, цепочки до 4, разрывы; блок 7 —
# места у костра (раздел 9.6): занятость, вставание, выход из мира.
extends GutTest

const B: Balance = preload("res://gameplay/balance.tres")

const EPS: float = 0.01


func test_pull_confirmed_when_hanging_and_close() -> void:
	var activity := ActivityAuthority.new()
	var event := activity.try_pull(7, 3, 120.0, true, 1.4, B)
	assert_eq(int(event["helper"]), 3)
	assert_eq(int(event["target"]), 7)
	assert_almost_eq(float(event["at"]), 120.0, EPS)


func test_pull_rejected_if_target_not_hanging() -> void:
	var activity := ActivityAuthority.new()
	assert_true(
		activity.try_pull(7, 3, 120.0, false, 1.4, B).is_empty(),
		"не висит — тянуть некого",
	)


func test_pull_rejected_if_self() -> void:
	var activity := ActivityAuthority.new()
	assert_true(
		activity.try_pull(7, 7, 120.0, true, 0.0, B).is_empty(),
		"сам себя не вытягивает",
	)


func test_pull_distance_boundary() -> void:
	var activity := ActivityAuthority.new()
	var limit: float = B.pull_radius + B.mob_hit_slack
	# Ровно на границе — допустимо (допуск на пинг), чуть дальше — нет.
	assert_false(activity.try_pull(7, 3, 120.0, true, limit, B).is_empty())
	assert_true(activity.try_pull(7, 3, 120.0, true, limit + 0.01, B).is_empty())


# --- Ворота руин (раздел 9.2) ---

## Первый тик инициализирует плиты без события; дальше шагаем по времени.
func _gate(activity: ActivityAuthority, plates: Array[int], count: int, at_gate: bool, t: float) -> Dictionary:
	return activity.update_ruins_gate(plates, count, at_gate, t, B)


func test_gate_opens_when_n_players_stand() -> void:
	var activity := ActivityAuthority.new()
	# Двое в мире: N = 2 — двое на плитах открывают.
	assert_true(_gate(activity, [0, 0, 0], 2, false, 10.0).is_empty(), "инициализация")
	var event := _gate(activity, [4, 7, 0], 2, false, 10.5)
	assert_true(bool(event["opened"]), "двое на плитах — открыто")
	var openers: Array = event["openers"]
	assert_eq(openers.size(), 2)
	assert_true(openers.has(4) and openers.has(7))


func test_gate_needs_min_of_three_and_players() -> void:
	var activity := ActivityAuthority.new()
	_gate(activity, [0, 0, 0], 5, false, 10.0)
	# Пятеро в мире: N = 3 — двоих мало, событие только о плитах.
	var event := _gate(activity, [4, 7, 0], 5, false, 10.5)
	assert_false(bool(event.get("opened", false)), "N=3: двоих мало")
	assert_eq((event["plates"] as Array).size(), 3)
	# Трое — открыто.
	event = _gate(activity, [4, 7, 9], 5, false, 11.0)
	assert_true(bool(event["opened"]), "N=3: трое открыли")


func test_gate_one_player_cannot_use_plates() -> void:
	var activity := ActivityAuthority.new()
	_gate(activity, [0, 0, 0], 1, false, 10.0)
	# Один игрок может встать только на одну плиту: N=2 недостижим.
	assert_false(
		bool(_gate(activity, [4, 0, 0], 1, false, 10.5).get("opened", false)),
		"одиночке плит недостаточно",
	)


func test_gate_solo_path_opens_after_60s() -> void:
	var activity := ActivityAuthority.new()
	_gate(activity, [0, 0, 0], 1, false, 10.0)
	# Одиночка пришёл к закрытым воротам в t=20: до 80 с — нет, после — открытие.
	assert_true(_gate(activity, [0, 0, 0], 1, true, 20.0).is_empty())
	assert_true(_gate(activity, [0, 0, 0], 1, true, 79.9).is_empty())
	var event := _gate(activity, [0, 0, 0], 1, true, 80.1)
	assert_true(bool(event["opened"]), "60 с у ворот — открылось само")
	assert_eq((event["openers"] as Array).size(), 0, "запасной путь — без открытых плит")


func test_gate_solo_path_resets_when_leaving() -> void:
	var activity := ActivityAuthority.new()
	_gate(activity, [0, 0, 0], 1, false, 10.0)
	_gate(activity, [0, 0, 0], 1, true, 40.0)  # копим 30 с
	_gate(activity, [0, 0, 0], 1, false, 50.0)  # ушёл — счёт сброшен
	assert_true(
		_gate(activity, [0, 0, 0], 1, true, 90.0).is_empty(),
		"после ухода ждём заново с нуля",
	)
	assert_true(bool(_gate(activity, [0, 0, 0], 1, true, 150.1).get("opened", false)))


func test_gate_closes_after_10_minutes() -> void:
	var activity := ActivityAuthority.new()
	_gate(activity, [0, 0, 0], 2, false, 100.0)
	_gate(activity, [4, 7, 0], 2, false, 100.5)
	assert_true(
		_gate(activity, [0, 0, 0], 2, false, 700.0).is_empty(),
		"600 с с открытия — ещё открыто",
	)
	var event := _gate(activity, [0, 0, 0], 2, false, 700.6)
	assert_true(bool(event["closed"]), "10 минут истекли — сброс")
	# После сброса ворота можно открыть снова.
	var reopened := _gate(activity, [4, 7, 0], 2, false, 701.0)
	assert_true(bool(reopened["opened"]), "после сброса открываются заново")


func test_gate_open_ignores_plates() -> void:
	var activity := ActivityAuthority.new()
	_gate(activity, [0, 0, 0], 2, false, 100.0)
	_gate(activity, [4, 7, 0], 2, false, 100.5)
	# Пока открыты — смена плит и запасной путь ничего не меняют.
	assert_true(_gate(activity, [0, 0, 0], 2, true, 200.0).is_empty())


func test_gate_state_roundtrip_for_world_state() -> void:
	var activity := ActivityAuthority.new()
	_gate(activity, [0, 0, 0], 2, false, 100.0)
	_gate(activity, [4, 7, 0], 2, false, 100.5)
	var state := activity.ruins_state()
	assert_true(bool(state["gate_open"]))
	assert_almost_eq(float(state["gate_opened_at"]), 100.5, EPS)
	activity.clear()
	state = activity.ruins_state()
	assert_false(bool(state["gate_open"]))
	assert_almost_eq(float(state["gate_opened_at"]), -1.0, EPS)


# --- Сундук (раздел 8): награда в радиусе 10 м в момент открытия ---

func test_chest_reward_in_radius() -> void:
	var entries: Array = [
		{"peer": 3, "pos": Vector3(58, 3, -48)},
		{"peer": 4, "pos": Vector3(58, 3, -56)},
		{"peer": 5, "pos": Vector3(80, 3, -50)},
	]
	var peers := ActivityAuthority.peers_in_radius(entries, Vector3(58, 3, -50), 10.0)
	assert_eq(peers.size(), 2)
	assert_true(peers.has(3) and peers.has(4), "в 10 м — оба, дальний нет")


# --- Лестницы смотровых (раздел 9.3) ---


func test_ladder_dropped_only_from_top() -> void:
	var activity := ActivityAuthority.new()
	activity.setup_ladders(4)
	# Внизу сбросить нельзя: поднявшимся должен быть сам просящий.
	assert_true(activity.try_drop_ladder(2, 100.0, false, B).is_empty(), "не на площадке")
	var event := activity.try_drop_ladder(2, 100.0, true, B)
	assert_eq(int(event["index"]), 2)
	assert_almost_eq(float(event["until"]), 100.0 + B.ladder_time, EPS)


func test_ladder_rejects_bad_index_and_empty_setup() -> void:
	var activity := ActivityAuthority.new()
	assert_true(activity.try_drop_ladder(0, 100.0, true, B).is_empty(), "без setup — нет")
	activity.setup_ladders(4)
	assert_true(activity.try_drop_ladder(-1, 100.0, true, B).is_empty(), "индекс < 0")
	assert_true(activity.try_drop_ladder(4, 100.0, true, B).is_empty(), "индекс ≥ числа смотровых")


func test_ladder_no_redrop_while_active() -> void:
	var activity := ActivityAuthority.new()
	activity.setup_ladders(1)
	activity.try_drop_ladder(0, 100.0, true, B)
	assert_true(
		activity.try_drop_ladder(0, 150.0, true, B).is_empty(),
		"пока висит — повторный сброс игнорируется",
	)
	# После истечения — можно снова.
	assert_eq(int(activity.update_ladders(160.1)["index"]), 0)
	var again := activity.try_drop_ladder(0, 170.0, true, B)
	assert_almost_eq(float(again["until"]), 170.0 + B.ladder_time, EPS)


func test_ladder_expires_after_60s() -> void:
	var activity := ActivityAuthority.new()
	activity.setup_ladders(2)
	activity.try_drop_ladder(1, 200.0, true, B)
	# До истечения — тишина, после — событие о скрытии ровно один раз.
	assert_true(activity.update_ladders(259.9).is_empty())
	var event := activity.update_ladders(260.0)
	assert_eq(int(event["index"]), 1)
	assert_false(bool(event["active"]))
	assert_true(activity.update_ladders(261.0).is_empty(), "второго события нет")


func test_ladder_state_roundtrip_and_clear() -> void:
	var activity := ActivityAuthority.new()
	activity.setup_ladders(3)
	activity.try_drop_ladder(0, 50.0, true, B)
	activity.try_drop_ladder(2, 60.0, true, B)
	var state := activity.ladders_state()
	assert_eq(state.size(), 2)
	assert_eq(int(state[0]["index"]), 0)
	assert_almost_eq(float(state[1]["until"]), 60.0 + B.ladder_time, EPS)
	activity.update_ladders(120.0)  # обе истекли — первая по очереди
	activity.update_ladders(130.0)
	assert_eq(activity.ladders_state().size(), 0, "истёкшие не попадают в world_state")
	activity.clear()
	activity.setup_ladders(3)
	assert_eq(activity.ladders_state().size(), 0)


# --- Золотой светлячок «на двоих» (раздел 8) ---


func test_firefly_first_hit_opens_window() -> void:
	var activity := ActivityAuthority.new()
	var event := activity.try_firefly_hit(13, 4, 100.0, B.firefly_respawn_sec, B)
	assert_eq(int(event["weakened"]), 4)
	assert_almost_eq(float(event["until"]), 100.0 + B.firefly_window, EPS)


func test_firefly_killed_by_two_different_players() -> void:
	var activity := ActivityAuthority.new()
	activity.try_firefly_hit(13, 4, 100.0, B.firefly_respawn_sec, B)
	var event := activity.try_firefly_hit(13, 7, 102.5, B.firefly_respawn_sec, B)
	var killers: Array = event["killed"]
	assert_eq(killers.size(), 2)
	assert_true(killers.has(4) and killers.has(7), "оба участника в награде")
	assert_almost_eq(
		float(event["respawn_at"]), 102.5 + B.firefly_respawn_sec, EPS
	)


func test_firefly_same_player_twice_does_not_kill() -> void:
	var activity := ActivityAuthority.new()
	activity.try_firefly_hit(13, 4, 100.0, B.firefly_respawn_sec, B)
	assert_true(
		activity.try_firefly_hit(13, 4, 102.0, B.firefly_respawn_sec, B).is_empty(),
		"тот же игрок — окна мало",
	)


func test_firefly_window_expires() -> void:
	var activity := ActivityAuthority.new()
	activity.try_firefly_hit(13, 4, 100.0, B.firefly_respawn_sec, B)
	# За пределами окна удар другого игрока не убивает — открывает новое окно.
	var second_at: float = 100.0 + B.firefly_window + 0.5
	var late := activity.try_firefly_hit(13, 7, second_at, B.firefly_respawn_sec, B)
	assert_eq(int(late["weakened"]), 7, "новое окно вместо убийства")
	# Теперь первый успевает в окно — пара убивает.
	var pair := activity.try_firefly_hit(
		13, 4, second_at + B.firefly_window - 0.1, B.firefly_respawn_sec, B
	)
	assert_eq((pair["killed"] as Array).size(), 2)


func test_firefly_state_reset_on_clear() -> void:
	var activity := ActivityAuthority.new()
	activity.try_firefly_hit(13, 4, 100.0, B.firefly_respawn_sec, B)
	activity.clear()
	# После сброса первый удар — снова окно, не убийство.
	var event := activity.try_firefly_hit(13, 7, 100.5, B.firefly_respawn_sec, B)
	assert_eq(int(event["weakened"]), 7)


# --- Маяки и Звездопад (раздел 7) ---


## Первый E при двух+ игроках окна не зажигает — ждём второго.
func test_beacon_first_press_opens_window() -> void:
	var activity := ActivityAuthority.new()
	activity.setup_beacons(5)
	assert_true(
		activity.try_beacon_light(2, 4, 100.0, 2, B).is_empty(),
		"один игрок маяк не зажигает",
	)


func test_beacon_pair_lights_within_window() -> void:
	var activity := ActivityAuthority.new()
	activity.setup_beacons(5)
	activity.try_beacon_light(2, 4, 100.0, 2, B)
	var event := activity.try_beacon_light(2, 7, 100.0 + B.beacon_pair_window - 0.5, 2, B)
	var lighters: Array = event["lighters"]
	assert_eq(lighters.size(), 2)
	assert_true(lighters.has(4) and lighters.has(7))
	assert_false(event.has("starfall_started_at"), "не последний маяк — без Звездопада")


func test_beacon_same_player_twice_does_not_light() -> void:
	var activity := ActivityAuthority.new()
	activity.setup_beacons(5)
	activity.try_beacon_light(2, 4, 100.0, 2, B)
	assert_true(
		activity.try_beacon_light(2, 4, 101.0, 2, B).is_empty(),
		"тот же игрок — окно лишь продлевается",
	)


func test_beacon_window_expires() -> void:
	var activity := ActivityAuthority.new()
	activity.setup_beacons(5)
	activity.try_beacon_light(2, 4, 100.0, 2, B)
	# Поздний E другого игрока открывает новое окно вместо зажигания.
	var late: float = 100.0 + B.beacon_pair_window + 0.5
	assert_true(activity.try_beacon_light(2, 7, late, 2, B).is_empty())
	var event := activity.try_beacon_light(
		2, 4, late + B.beacon_pair_window - 0.1, 2, B
	)
	assert_eq((event["lighters"] as Array).size(), 2, "пара в новом окне зажигает")


func test_beacon_solo_lights_immediately() -> void:
	var activity := ActivityAuthority.new()
	activity.setup_beacons(5)
	# Запасной путь (раздел 7): один игрок в мире, E удержано 8 с.
	var event := activity.try_beacon_light(1, 9, 200.0, 1, B)
	assert_eq(int(event["lighters"][0]), 9)
	# Горящий маяк повторно не зажечь.
	assert_true(activity.try_beacon_light(1, 9, 201.0, 1, B).is_empty())
	assert_true(activity.try_beacon_light(1, 8, 201.0, 2, B).is_empty())


func test_starfall_starts_on_fifth_beacon() -> void:
	var activity := ActivityAuthority.new()
	activity.setup_beacons(5)
	for i: int in 4:
		assert_false(
			activity.try_beacon_light(i, 20 + i, 300.0, 1, B).has("starfall_started_at"),
			"маяк %d — не последний" % i,
		)
	var event := activity.try_beacon_light(4, 4, 400.0, 2, B)
	assert_true(event.is_empty(), "первый из пары — окно")
	event = activity.try_beacon_light(4, 7, 401.0, 2, B)
	assert_almost_eq(float(event["starfall_started_at"]), 401.0, EPS)
	var state := activity.beacons_state()
	assert_eq((state["lit"] as Array).size(), 5, "все пять горят")
	assert_almost_eq(float(state["starfall_started_at"]), 401.0, EPS)


func test_starfall_ends_then_beacons_reset_cycle_repeats() -> void:
	var activity := ActivityAuthority.new()
	activity.setup_beacons(5)
	for i: int in 5:
		activity.try_beacon_light(i, 20 + i, 100.0, 1, B)
	assert_true(activity.update_beacons(100.0 + B.starfall_duration - 0.1, B).is_empty())
	# Конец Звездопада — один раз; маяки ещё горят.
	assert_true(activity.update_beacons(100.0 + B.starfall_duration, B).has("starfall_ended"))
	assert_true(activity.update_beacons(100.0 + B.starfall_duration + 1.0, B).is_empty())
	# Гашение — через beacon_reset_sec после конца.
	var reset_at: float = 100.0 + B.starfall_duration + B.beacon_reset_sec
	assert_true(activity.update_beacons(reset_at - 0.1, B).is_empty())
	assert_true(activity.update_beacons(reset_at, B).has("beacons_reset"))
	var state := activity.beacons_state()
	assert_eq((state["lit"] as Array).size(), 0, "все погасли")
	assert_almost_eq(float(state["starfall_started_at"]), -1.0, EPS)
	# Цикл заново: маяк снова зажигается.
	assert_eq(
		int(activity.try_beacon_light(0, 30, reset_at + 5.0, 1, B)["lighters"][0]), 30
	)


func test_star_first_take_wins() -> void:
	var activity := ActivityAuthority.new()
	activity.setup_beacons(5)
	assert_true(
		activity.try_take_star(3, 7, 50.0, B).is_empty(),
		"до Звездопада звёзд нет",
	)
	for i: int in 5:
		activity.try_beacon_light(i, 20 + i, 100.0, 1, B)
	var event := activity.try_take_star(3, 7, 101.0, B)
	assert_eq(int(event["collector"]), 7)
	assert_true(
		activity.try_take_star(3, 8, 102.0, B).is_empty(),
		"вторая попытка на ту же звезду отклонена",
	)
	# Упавшая до конца звезда доживает star_lifetime — окно сбора.
	var edge: float = 100.0 + B.starfall_duration + B.star_lifetime
	assert_false(activity.try_take_star(4, 8, edge - 0.1, B).is_empty())
	assert_true(activity.try_take_star(5, 8, edge + 0.1, B).is_empty())
	assert_eq(activity.stars_taken_state().size(), 2)


func test_beacons_state_reset_on_clear() -> void:
	var activity := ActivityAuthority.new()
	activity.setup_beacons(5)
	for i: int in 5:
		activity.try_beacon_light(i, 20 + i, 100.0, 1, B)
	activity.clear()
	assert_eq((activity.beacons_state()["lit"] as Array).size(), 0)
	assert_eq(activity.stars_taken_state().size(), 0)
	activity.setup_beacons(5)
	assert_false(activity.try_beacon_light(0, 9, 100.0, 1, B).is_empty())


# --- «За руку» (раздел 9.5) ---

func test_hand_link_confirmed_when_close() -> void:
	var activity := ActivityAuthority.new()
	var event := activity.try_hand_link(4, 7, 1.5, B)
	assert_eq(int(event["leader"]), 4, "инициатор ведёт")
	assert_eq(int(event["follower"]), 7)
	assert_eq(activity.hand_links_state().size(), 1)


func test_hand_link_rejected_self_or_far() -> void:
	var activity := ActivityAuthority.new()
	assert_true(
		activity.try_hand_link(4, 4, 0.0, B).is_empty(),
		"сам с собой не связывается",
	)
	var limit: float = B.hand_link_radius + B.mob_hit_slack
	# Ровно на границе — допустимо (допуск на пинг), чуть дальше — нет.
	assert_false(activity.try_hand_link(4, 7, limit, B).is_empty())
	assert_true(
		activity.try_hand_link(9, 8, limit + 0.01, B).is_empty(),
		"слишком далеко для нового приглашения",
	)


func test_hand_link_roles_taken() -> void:
	var activity := ActivityAuthority.new()
	assert_false(activity.try_hand_link(4, 7, 1.0, B).is_empty(), "связь установлена")
	assert_true(activity.try_hand_link(4, 8, 1.0, B).is_empty(), "у 4 уже есть ведомый")
	assert_true(activity.try_hand_link(8, 7, 1.0, B).is_empty(), "у 7 уже есть ведущий")
	# Из свободных игроков новая пара — можно.
	assert_false(activity.try_hand_link(8, 9, 1.0, B).is_empty())


func test_hand_chain_limited_to_four() -> void:
	var activity := ActivityAuthority.new()
	# Цепочка D → C → B → A (раздел 9.5: «C держит B, B держит A», до 4).
	assert_false(activity.try_hand_link(2, 1, 1.0, B).is_empty(), "B ведёт A")
	assert_false(activity.try_hand_link(3, 2, 1.0, B).is_empty(), "C ведёт B")
	assert_false(activity.try_hand_link(4, 3, 1.0, B).is_empty(), "D ведёт C — цепочка из 4")
	assert_true(
		activity.try_hand_link(5, 4, 1.0, B).is_empty(),
		"пятый в цепочку не встаёт",
	)
	assert_eq(activity.hand_links_state().size(), 3)


func test_hand_release_by_either_side() -> void:
	var activity := ActivityAuthority.new()
	activity.try_hand_link(4, 7, 1.0, B)
	var event := activity.try_hand_release(7)
	assert_eq(int(event["leader"]), 4, "отпустил ведомый")
	assert_eq(int(event["follower"]), 7)
	assert_true(activity.hand_links_state().is_empty())
	activity.try_hand_link(4, 7, 1.0, B)
	event = activity.try_hand_release(4)
	assert_eq(int(event["leader"]), 4, "отпустил ведущий")
	assert_true(
		activity.try_hand_release(9).is_empty(),
		"не в связи — отпускать нечего",
	)


func test_hand_links_broken_by_distance_or_leaving() -> void:
	var activity := ActivityAuthority.new()
	activity.try_hand_link(4, 7, 1.0, B)
	var entries: Array[Dictionary] = [
		{"peer": 4, "pos": Vector3.ZERO, "floor": true},
		{"peer": 7, "pos": Vector3(B.hand_break_distance + B.mob_hit_slack + 0.01, 0.0, 0.0), "floor": true},
	]
	var event := activity.update_hand_links(entries, B)
	assert_eq(int(event["follower"]), 7, "разрыв по расстоянию")
	assert_true(activity.hand_links_state().is_empty())
	# Выход из мира рвёт связь, даже если расстояние нормальное.
	activity.try_hand_link(4, 7, 1.0, B)
	event = activity.update_hand_links([{"peer": 4, "pos": Vector3.ZERO, "floor": true}], B)
	assert_eq(int(event["leader"]), 4, "разрыв: ведомый вышел из мира")
	# Оба рядом и в мире — связь живёт.
	activity.try_hand_link(4, 7, 1.0, B)
	entries = [
		{"peer": 4, "pos": Vector3.ZERO, "floor": true},
		{"peer": 7, "pos": Vector3(2.0, 0.0, 0.0), "floor": true},
	]
	assert_true(activity.update_hand_links(entries, B).is_empty())


func test_hand_state_reset_on_clear() -> void:
	var activity := ActivityAuthority.new()
	activity.try_hand_link(4, 7, 1.0, B)
	activity.clear()
	assert_true(activity.hand_links_state().is_empty())
	assert_false(
		activity.try_hand_link(4, 7, 1.0, B).is_empty(),
		"после clear связь снова возможна",
	)


# --- Места у костра (раздел 9.6) ---

func test_sit_confirmed_when_close() -> void:
	var activity := ActivityAuthority.new()
	activity.setup_seats(8)
	var event := activity.try_sit(4, 2, 1.2, B)
	assert_eq(int(event["seat"]), 2)
	assert_eq(int(event["peer"]), 4)
	assert_eq(int(activity.seats_state()[2]), 4, "место занято")


func test_sit_rejected_if_taken_or_far_or_bad_index() -> void:
	var activity := ActivityAuthority.new()
	activity.setup_seats(8)
	assert_false(activity.try_sit(4, 2, 1.2, B).is_empty(), "первый садится")
	assert_true(
		activity.try_sit(7, 2, 1.2, B).is_empty(),
		"занято второму отказ",
	)
	var limit: float = B.campfire_seat_radius + B.mob_hit_slack
	# Ровно на границе — допустимо (допуск на пинг), чуть дальше — нет.
	assert_false(activity.try_sit(7, 3, limit, B).is_empty())
	assert_true(
		activity.try_sit(7, 3, limit + 0.01, B).is_empty(),
		"слишком далеко от лавки",
	)
	assert_true(activity.try_sit(7, 8, 1.0, B).is_empty(), "индекс вне мест")
	assert_true(activity.try_sit(7, -1, 1.0, B).is_empty(), "отрицательный индекс")


func test_sit_moves_player_from_old_seat() -> void:
	var activity := ActivityAuthority.new()
	activity.setup_seats(8)
	activity.try_sit(4, 2, 1.2, B)
	# Переселение на соседнюю лавку освобождает прежнее место.
	assert_false(activity.try_sit(4, 5, 1.2, B).is_empty())
	assert_eq(int(activity.seats_state()[2]), 0, "старое место свободно")
	assert_eq(int(activity.seats_state()[5]), 4)


func test_stand_up_frees_seat() -> void:
	var activity := ActivityAuthority.new()
	activity.setup_seats(8)
	activity.try_sit(4, 2, 1.2, B)
	var event := activity.stand_up(4)
	assert_eq(int(event["seat"]), 2)
	assert_eq(int(activity.seats_state()[2]), 0)
	assert_true(activity.stand_up(4).is_empty(), "уже не сидит")
	# Освободившееся место доступно другому.
	assert_false(activity.try_sit(7, 2, 1.2, B).is_empty())


func test_seat_freed_when_player_leaves_world() -> void:
	var activity := ActivityAuthority.new()
	activity.setup_seats(8)
	activity.try_sit(4, 2, 1.2, B)
	activity.try_sit(7, 5, 1.2, B)
	# Оба в мире — ничего не меняется.
	var both: Array[Dictionary] = [
		{"peer": 4, "pos": Vector3.ZERO, "floor": true},
		{"peer": 7, "pos": Vector3.ZERO, "floor": true},
	]
	assert_true(activity.update_seats(both).is_empty(), "оба в мире — сидят")
	var event := activity.update_seats([{"peer": 7, "pos": Vector3.ZERO, "floor": true}])
	assert_eq(int(event["seat"]), 2, "вышедший из мира потерял место")
	assert_eq(int(event["peer"]), 4)
	assert_eq(int(activity.seats_state()[2]), 0)
	assert_eq(int(activity.seats_state()[5]), 7, "второй продолжает сидеть")


func test_seats_state_reset_on_clear() -> void:
	var activity := ActivityAuthority.new()
	activity.setup_seats(8)
	activity.try_sit(4, 2, 1.2, B)
	activity.clear()
	assert_true(activity.seats_state().is_empty())
	# После clear места инициализируются заново и свободны.
	activity.setup_seats(8)
	assert_false(activity.try_sit(4, 2, 1.2, B).is_empty(), "место свободно после clear")
	assert_false(activity.stand_up(4).is_empty(), "место снова занято")
