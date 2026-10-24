# Обязательные тесты раздела 18 (П5): чистая логика хоста активностей.
# Осталось после вычистки наследия Blockparty (born-unblessed): лестницы
# смотровых (раздел 9.3) и места у костра (раздел 9.6). Вытягивание,
# ворота руин и «за руку» (разделы 9.1, 9.2, 9.5) удалены вместе
# с механиками; эмоции (9.7) удалены отдельной группой.
extends GutTest

const B: Balance = preload("res://gameplay/balance.tres")

const EPS: float = 0.01


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
