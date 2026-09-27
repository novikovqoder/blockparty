# Сверка gameplay/balance.tres со стартовыми значениями разделов 4–6 SPEC:
# если значение меняют намеренно — правят SPEC и этот тест одновременно.
extends GutTest

const B: Balance = preload("res://gameplay/balance.tres")
const EPS: float = 0.0001


func test_movement_section4() -> void:
	assert_almost_eq(B.run_speed, 260.0, EPS)
	assert_almost_eq(B.accel_ground, 1800.0, EPS)
	assert_almost_eq(B.friction_ground, 2200.0, EPS)
	assert_almost_eq(B.air_control, 0.7, EPS)
	assert_almost_eq(B.jump_speed, 520.0, EPS)
	assert_almost_eq(B.gravity, 1400.0, EPS)
	assert_almost_eq(B.gravity_fall_multiplier, 1.4, EPS)
	assert_almost_eq(B.max_fall_speed, 900.0, EPS)
	assert_almost_eq(B.coyote_time, 0.10, EPS)
	assert_almost_eq(B.jump_buffer_time, 0.10, EPS)
	assert_almost_eq(B.jump_cut_factor, 0.45, EPS)
	assert_almost_eq(B.hitbox_width, 28.0, EPS)
	assert_almost_eq(B.hitbox_height, 44.0, EPS)
	assert_almost_eq(B.head_jump_bonus, 1.25, EPS)


func test_attack_section4() -> void:
	assert_almost_eq(B.attack_width, 40.0, EPS)
	assert_almost_eq(B.attack_height, 32.0, EPS)
	assert_almost_eq(B.attack_active_time, 0.12, EPS)
	assert_almost_eq(B.attack_cooldown, 0.35, EPS)


func test_run_limits_section5() -> void:
	assert_almost_eq(B.run_time_limit, 600.0, EPS)
	assert_almost_eq(B.hang_time, 8.0, EPS)
	assert_almost_eq(B.start_countdown_time, 3.0, EPS)


func test_rewards_section6() -> void:
	assert_eq(B.coin_value, 1)
	assert_eq(B.mob_kill_coins, 1)
	assert_eq(B.bird_hits_to_die, 1)
	assert_eq(B.critter_hits_to_die, 1)
	assert_eq(B.golden_hits_to_die, 2)
	assert_eq(B.golden_kill_coins, 10)
	assert_eq(B.pull_up_coins, 3)
	assert_eq(B.gate_coins, 2)
	assert_eq(B.finish_coins, 5)
	assert_almost_eq(B.hit_accept_range, 96.0, EPS)


func test_jump_height_matches_spec() -> void:
	# Раздел 4: высота обычного прыжка при этих значениях — около 96 px
	# (520² / (2 × 1400) = 96.57 — SPEC округляет до 96).
	var height: float = pow(B.jump_speed, 2.0) / (2.0 * B.gravity)
	assert_almost_eq(height, 96.0, 1.0)


func test_palette_loads() -> void:
	var pal: Palette = preload("res://assets/palette.tres")
	assert_ne(pal.ground, Color.BLACK)
	assert_ne(pal.player_body, Color.BLACK)
