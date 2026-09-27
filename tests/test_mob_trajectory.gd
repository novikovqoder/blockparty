# Тест траекторий мобов и движущихся платформ как чистых функций времени
# (раздел 16 SPEC: одинаковый результат при одинаковом входе).
extends GutTest

const EPS: float = 0.001


func test_bird_same_input_same_output() -> void:
	var params := {"span": 480.0, "period": 5.0, "dir": 1.0, "wave_amp": 26.0, "wave_period": 2.2}
	for i: int in 50:
		var t := 0.137 * float(i)
		var a := BirdMob.trajectory(params, t)
		var b := BirdMob.trajectory(params, t)
		assert_almost_eq(a.x, b.x, EPS)
		assert_almost_eq(a.y, b.y, EPS)


func test_bird_stays_within_span() -> void:
	var params := {"span": 480.0, "period": 5.0, "dir": 1.0, "wave_amp": 26.0, "wave_period": 2.2}
	for i: int in 200:
		var t := 0.05 * float(i)
		var offset := BirdMob.trajectory(params, t)
		assert_true(absf(offset.x) <= 240.0 + EPS, "x=%f выходит за половину span" % offset.x)
		assert_true(absf(offset.y) <= 26.0 + EPS)


func test_bird_direction_flips_pattern() -> void:
	# dir = -1 зеркалит патруль по x.
	var params := {"span": 400.0, "period": 4.0, "dir": 1.0, "wave_amp": 0.0, "wave_period": 1.0}
	var mirrored := params.duplicate()
	mirrored["dir"] = -1.0
	var t := 0.7
	assert_almost_eq(
		BirdMob.trajectory(params, t).x,
		-BirdMob.trajectory(mirrored, t).x,
		EPS
	)


func test_critter_same_input_same_output() -> void:
	var params := {"span": 360.0, "period": 4.0}
	for i: int in 50:
		var t := 0.211 * float(i)
		var a := CritterMob.trajectory(params, t)
		var b := CritterMob.trajectory(params, t)
		assert_almost_eq(a.x, b.x, EPS)
		assert_eq(a.y, 0.0, "зверёк бегает по земле")


func test_critter_turns_at_edges() -> void:
	var params := {"span": 360.0, "period": 4.0}
	# Крайние точки: в начале и в середине периода зверёк у краёв, в четверти — в центре.
	var edge_a := CritterMob.trajectory(params, 0.0)
	var mid := CritterMob.trajectory(params, 1.0)  # четверть периода
	var edge_b := CritterMob.trajectory(params, 2.0)  # полпериода
	assert_almost_eq(edge_a.x, -180.0, EPS)
	assert_almost_eq(mid.x, 0.0, EPS)
	assert_almost_eq(edge_b.x, 180.0, EPS)


func test_triangle_wave() -> void:
	assert_almost_eq(Mob.triangle_wave(0.0), -1.0, EPS)
	assert_almost_eq(Mob.triangle_wave(0.5), 0.0, EPS)
	assert_almost_eq(Mob.triangle_wave(1.0), 1.0, EPS)
	assert_almost_eq(Mob.triangle_wave(1.5), 0.0, EPS)
	assert_almost_eq(Mob.triangle_wave(2.0), -1.0, EPS)
	assert_almost_eq(Mob.triangle_wave(-0.5), 0.0, EPS, "отрицательная фаза заворачивается")


func test_moving_platform_bounded_and_deterministic() -> void:
	var params := {"axis": Vector2.RIGHT, "amp": 160.0, "period": 4.6, "phase": 0.0}
	for i: int in 200:
		var t := 0.05 * float(i)
		var a := MovingPlatform.trajectory(params, t)
		var b := MovingPlatform.trajectory(params, t)
		assert_almost_eq(a.x, b.x, EPS)
		assert_almost_eq(a.y, 0.0, EPS, "горизонтальная платформа не drift'ит по y")
		assert_true(absf(a.x) <= 160.0 + EPS)
	# Вертикальная ось тоже допустима.
	var vertical := {"axis": Vector2.UP, "amp": 64.0, "period": 3.0, "phase": 0.0}
	var offset := MovingPlatform.trajectory(vertical, 0.75)
	assert_almost_eq(offset.x, 0.0, EPS)
	assert_true(absf(offset.y) > 0.0)
