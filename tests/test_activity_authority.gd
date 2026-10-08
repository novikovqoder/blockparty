# Обязательные тесты раздела 18 (П5): чистая логика хоста активностей.
# Блок 1 — вытягивание из расщелины (раздел 9.1): хост подтверждает, только
# если target висит, helper — другой игрок и он достаточно близко.
# Блоки 2+ (ворота, маяки, костёр, «за руку») добавятся здесь же.
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
