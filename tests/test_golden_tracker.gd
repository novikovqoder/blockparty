# Тест логики золотой цели (gameplay/mobs/golden_tracker.gd, разделы 6, 7.4):
# цель убивается только ударами двух РАЗНЫХ игроков в пределах
# golden_hit_window (3 с); тот же игрок или истёкшее окно цель «заводят» заново.
extends GutTest


func test_two_different_players_in_window_kill() -> void:
	var tracker := GoldenTracker.new()
	var first := tracker.register_hit(10, 1, 1.0)
	assert_true(first["first_hit"])
	assert_false(first["killed"])
	var second := tracker.register_hit(10, 2, 3.5)  # окно 3 с: 3,5 − 1,0 ≤ 3
	assert_true(second["killed"])
	assert_eq(second["participants"], [1, 2])


func test_same_player_twice_does_not_kill() -> void:
	var tracker := GoldenTracker.new()
	tracker.register_hit(10, 1, 1.0)
	var again := tracker.register_hit(10, 1, 2.0)
	assert_false(again["killed"], "удар того же игрока цель не добивает")


func test_expired_window_restarts() -> void:
	var tracker := GoldenTracker.new()
	tracker.register_hit(10, 1, 1.0)
	var late := tracker.register_hit(10, 2, 5.0)  # 5,0 − 1,0 > 3 — окно истекло
	assert_false(late["killed"], "поздний удар начинает новое окно")
	var finish := tracker.register_hit(10, 1, 6.5)  # 6,5 − 5,0 ≤ 3 — второй «разный»
	assert_true(finish["killed"])
	assert_eq(finish["participants"], [2, 1])


func test_state_cleared_after_kill() -> void:
	var tracker := GoldenTracker.new()
	tracker.register_hit(10, 1, 1.0)
	tracker.register_hit(10, 2, 2.0)  # убита
	var fresh := tracker.register_hit(10, 1, 10.0)
	assert_false(fresh["killed"])
	assert_true(fresh["first_hit"], "после смерти цель заводится заново")


func test_reset_clears_hits() -> void:
	var tracker := GoldenTracker.new()
	tracker.register_hit(10, 1, 1.0)
	tracker.reset()
	var after := tracker.register_hit(10, 2, 1.5)
	assert_false(after["killed"], "после reset предыдущих ударов нет")
