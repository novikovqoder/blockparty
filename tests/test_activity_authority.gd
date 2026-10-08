# Обязательные тесты раздела 18 (П5): чистая логика хоста активностей.
# Блок 1 — вытягивание из расщелины (раздел 9.1); блок 2 — ворота руин,
# плиты и сундук (разделы 8, 9.2): N = min(3, игроков) ≥ 2, запасной путь
# одиночки 60 с у ворот, сброс 10 минут. Блоки 5+ (маяки, костёр, «за
# руку») добавятся здесь же.
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
