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
