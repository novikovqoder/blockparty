# Обязательный тест раздела 18 «расписание возрождений» + авторитет хоста
# (разделы 8, 10): хост проверяет удар (дистанция с допуском, перезарядка,
# моб жив), монеты — «первый запрос выигрывает», возрождение вычисляется
# от world_time, состояние чистится и пакуется в world_state.
extends GutTest

const B: Balance = preload("res://gameplay/balance.tres")

const EPS: float = 0.001


func _kill(
	authority: HostAuthority, spawn_id: int, peer: int, at: float,
	mob_at: Vector3, killer_at: Vector3,
) -> Dictionary:
	return authority.try_kill_mob(
		spawn_id, peer, at, mob_at, killer_at, B.mob_respawn_sec, B
	)


func test_kill_close_mob_schedules_respawn() -> void:
	var authority := HostAuthority.new()
	var event := _kill(authority, 7, 2, 100.0, Vector3(10, 3, 0), Vector3(10, 3, 2.4))
	assert_eq(int(event["spawn_id"]), 7, "событие убийства выдано")
	assert_almost_eq(
		float(event["respawn_at"]), 100.0 + B.mob_respawn_sec, EPS,
		"возрождение через mob_respawn_sec",
	)
	assert_false(authority.is_mob_alive(7, 100.0), "моб мёртв сразу после удара")
	assert_true(authority.is_mob_alive(7, 100.0 + B.mob_respawn_sec), "возрождён по расписанию")


func test_dead_mob_rejects_second_killer() -> void:
	var authority := HostAuthority.new()
	assert_ne(_kill(authority, 7, 2, 100.0, Vector3.ZERO, Vector3(0, 0, 1)), {})
	var second := _kill(authority, 7, 5, 100.2, Vector3.ZERO, Vector3(0, 0, 1))
	assert_eq(second, {}, "моб уже мёртв — второй удар отклонён")


func test_far_hit_rejected() -> void:
	var authority := HostAuthority.new()
	var allowed: float = B.mob_hit_distance + B.mob_hit_slack
	var just_ok := _kill(authority, 1, 2, 10.0, Vector3.ZERO, Vector3(allowed, 0, 0))
	assert_ne(just_ok, {}, "на границе допуска — засчитано (пинг сдвинул снапшот)")
	var too_far := _kill(authority, 2, 2, 10.0, Vector3.ZERO, Vector3(allowed + 0.1, 0, 0))
	assert_eq(too_far, {}, "за границей допуска — отклонено")


func test_attack_cooldown_rate_limits() -> void:
	# Раздел 8: хост проверяет перезарядку — запросы одного игрока
	# не чаще attack_cooldown (хост не видит взмахов клиента).
	var authority := HostAuthority.new()
	assert_ne(_kill(authority, 1, 2, 100.0, Vector3.ZERO, Vector3(0, 0, 1)), {})
	assert_eq(_kill(authority, 2, 2, 100.1, Vector3.ZERO, Vector3(0, 0, 1)), {},
		"следующий удар того же игрока слишком рано — отклонён")
	assert_ne(_kill(authority, 2, 3, 100.1, Vector3.ZERO, Vector3(0, 0, 1)), {},
		"другой игрок — можно")
	assert_ne(_kill(authority, 4, 2, 100.0 + B.attack_cooldown + 0.01, Vector3.ZERO, Vector3(0, 0, 1)), {},
		"после перезарядки — можно")


func test_coin_first_request_wins() -> void:
	var authority := HostAuthority.new()
	var first := authority.try_take_coin(41, 3, 500.0, B.coin_respawn_sec)
	assert_eq(int(first["spawn_id"]), 41)
	assert_almost_eq(float(first["respawn_at"]), 500.0 + B.coin_respawn_sec, EPS)
	var second := authority.try_take_coin(41, 4, 500.05, B.coin_respawn_sec)
	assert_eq(second, {}, "второй запрос на ту же монету отклонён")


func test_prune_drops_respawned_entries() -> void:
	var authority := HostAuthority.new()
	_kill(authority, 1, 2, 100.0, Vector3.ZERO, Vector3(0, 0, 1))
	authority.try_take_coin(2, 3, 100.0, B.coin_respawn_sec)
	authority.prune(100.0 + B.mob_respawn_sec - 0.01)
	assert_eq(authority.dead_mobs.size(), 1, "моб ещё мёртв")
	authority.prune(100.0 + B.mob_respawn_sec)
	assert_eq(authority.dead_mobs.size(), 0, "возрождённый моб убран из состояния")
	assert_eq(authority.taken_coins.size(), 1, "монета ещё не возродилась (300 с)")
	authority.prune(100.0 + B.coin_respawn_sec)
	assert_eq(authority.taken_coins.size(), 0)


func test_entries_feed_world_state() -> void:
	# Словари для WorldState.pack: поздно вошедший видит тех же мёртвых
	# мобов и подобранные монеты с одинаковым временем возрождения.
	var authority := HostAuthority.new()
	_kill(authority, 3, 2, 100.0, Vector3.ZERO, Vector3(0, 0, 1))
	authority.try_take_coin(41, 3, 120.0, B.coin_respawn_sec)
	var dead: Array = authority.dead_mob_entries()
	var taken: Array = authority.taken_coin_entries()
	assert_eq(dead.size(), 1)
	assert_eq(int(dead[0]["spawn_id"]), 3)
	assert_almost_eq(float(dead[0]["respawn_at"]), 100.0 + B.mob_respawn_sec, EPS)
	assert_eq(taken.size(), 1)
	assert_eq(int(taken[0]["spawn_id"]), 41)


func test_clear_resets_world() -> void:
	var authority := HostAuthority.new()
	_kill(authority, 1, 2, 100.0, Vector3.ZERO, Vector3(0, 0, 1))
	authority.try_take_coin(2, 3, 100.0, B.coin_respawn_sec)
	authority.clear()
	assert_eq(authority.dead_mobs.size(), 0)
	assert_eq(authority.taken_coins.size(), 0)
