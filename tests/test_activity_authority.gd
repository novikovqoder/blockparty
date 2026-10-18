# Обязательные тесты раздела 18 (П5): чистая логика хоста активностей.
# Блок 1 — вытягивание из расщелины (раздел 9.1); блок 2 — ворота руин
# и плиты (раздел 9.2): N = min(3, игроков) ≥ 2, запасной путь одиночки
# 60 с у ворот, сброс 10 минут; блок 5 — «за руку» (раздел 9.5): роли,
# цепочки до 4, разрывы; блок 6 — места у костра (раздел 9.6): занятость,
# вставание, выход из мира; блок 7 — эмоции (раздел 9.7): перезарядка 1 с;
# блок 8 — запасной путь одиночки у светлячка (раздел 9.4).
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
	var limit: float = B.pull_radius + B.ping_slack
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
	var limit: float = B.hand_link_radius + B.ping_slack
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
		{"peer": 7, "pos": Vector3(B.hand_break_distance + B.ping_slack + 0.01, 0.0, 0.0), "floor": true},
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
	var limit: float = B.campfire_seat_radius + B.ping_slack
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


# --- Эмоции (раздел 9.7) ---

func test_emote_confirmed_then_cooldown() -> void:
	var activity := ActivityAuthority.new()
	var event := activity.try_emote(4, 0, 100.0, B)
	assert_eq(int(event["emote"]), 0)
	# Перезарядка 1 с: подряд — отказ, после паузы — снова можно.
	assert_true(
		activity.try_emote(4, 1, 100.5, B).is_empty(),
		"перезарядка не прошла",
	)
	var edge: float = 100.0 + B.emote_cooldown
	assert_false(activity.try_emote(4, 1, edge, B).is_empty())
	# Кулдаун у каждого свой.
	assert_false(activity.try_emote(7, 2, 100.5, B).is_empty(), "другой игрок без паузы")


func test_emote_rejected_bad_index_and_clear() -> void:
	var activity := ActivityAuthority.new()
	assert_true(activity.try_emote(4, -1, 100.0, B).is_empty(), "отрицательный индекс")
	assert_true(
		activity.try_emote(4, Protocol.EMOTE_KEYS.size(), 100.0, B).is_empty(),
		"индекс за пределами колеса",
	)
	activity.try_emote(4, 0, 100.0, B)
	assert_true(activity.try_emote(4, 1, 100.5, B).is_empty(), "кулдаун держится")
	activity.clear()
	assert_false(
		activity.try_emote(4, 1, 100.5, B).is_empty(),
		"после clear кулдаун сброшен",
	)
