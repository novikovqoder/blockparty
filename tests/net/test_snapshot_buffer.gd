# Буфер 3D-снапшотов (раздел 10): отбрасывание старых seq с учётом wrap
# uint16, линейная интерполяция позиции, интерполяция поворота по кратчайшей
# дуге, лимит экстраполяции и телепорт дальше 5 м без сглаживания.
extends GutTest

const EPS: float = 0.01


func _snap(seq: int, x: float, vx: float, t: int, yaw: float = 0.0) -> Dictionary:
	return {
		"seq": seq, "x": x, "y": 0.0, "z": 0.0, "yaw": yaw,
		"vx": vx, "vy": 0.0, "vz": 0.0, "anim": 0, "flags": 0, "t": t,
	}


func test_stale_and_duplicate_seq_rejected() -> void:
	var buffer := SnapshotBuffer.new()
	assert_true(buffer.push(_snap(5, 0.0, 0.0, 1000), 1000))
	assert_false(buffer.push(_snap(5, 0.0, 0.0, 1050), 1050), "дубликат seq")
	assert_false(buffer.push(_snap(4, 0.0, 0.0, 1100), 1100), "старый seq")
	assert_true(buffer.push(_snap(6, 10.0, 0.0, 1150), 1150))


func test_seq_wrap_accepted() -> void:
	var buffer := SnapshotBuffer.new()
	for seq: int in [65533, 65534, 65535, 0, 1]:
		assert_true(buffer.push(_snap(seq, 0.0, 0.0, 1000 + seq * 10), 2000), "seq %d принят" % seq)
	assert_false(buffer.push(_snap(65534, 0.0, 0.0, 3000), 3000), "старый после wrap")


func test_interpolation_between_samples() -> void:
	var buffer := SnapshotBuffer.new()
	buffer.push(_snap(1, 0.0, 0.0, 1000), 1000)
	buffer.push(_snap(2, 100.0, 0.0, 1100), 1100)
	var mid: Dictionary = buffer.sample(1050)
	assert_almost_eq(float(mid["x"]), 50.0, EPS)
	var quarter: Dictionary = buffer.sample(1025)
	assert_almost_eq(float(quarter["x"]), 25.0, EPS)


func test_yaw_interpolates_shortest_arc() -> void:
	# Раздел 10: поворот интерполируется по кратчайшей дуге — от 3.0 к −3.0
	# (через π, расхождение всего ~0.28 рад), а не «внутрь» через ноль.
	var buffer := SnapshotBuffer.new()
	buffer.push(_snap(1, 0.0, 0.0, 1000, 3.0), 1000)
	buffer.push(_snap(2, 10.0, 0.0, 1100, -3.0), 1100)
	var mid: Dictionary = buffer.sample(1050)
	assert_almost_eq(float(mid["yaw"]), PI, 0.01)
	# Длинный путь (через ноль) дал бы 0.0 — проверяем, что его нет.
	assert_almost_eq(float(mid["yaw"]), 3.14159, 0.01)


func test_extrapolation_limited_then_frozen() -> void:
	var buffer := SnapshotBuffer.new()
	buffer.push(_snap(1, 0.0, 20.0, 1000), 1000)
	# 75 мс вперёд — экстраполяция скоростью: 0 + 20 * 0.075 = 1.5 м.
	var ahead: Dictionary = buffer.sample(1075)
	assert_almost_eq(float(ahead["x"]), 1.5, 0.1)
	assert_false(bool(ahead["frozen"]))
	# Ровно на лимите 150 мс — ещё экстраполяция: 20 * 0.150 = 3 м.
	var at_limit: Dictionary = buffer.sample(1150)
	assert_almost_eq(float(at_limit["x"]), 3.0, 0.1)
	assert_false(bool(at_limit["frozen"]))
	# Дальше лимита — персонаж замирает и больше не двигается.
	var far: Dictionary = buffer.sample(1300)
	assert_true(bool(far["frozen"]))
	assert_almost_eq(float(far["x"]), 3.0, EPS)
	assert_almost_eq(float(buffer.sample(2000)["x"]), 3.0, EPS)


func test_teleport_beyond_5m() -> void:
	var buffer := SnapshotBuffer.new()
	buffer.push(_snap(1, 0.0, 0.0, 1000), 1000)
	buffer.sample(1000)  # отрисовались в 0
	buffer.push(_snap(2, 20.0, 0.0, 1100), 1100)
	var jump: Dictionary = buffer.sample(1050)
	assert_true(bool(jump["teleported"]), "скачок 10 м — телепорт")
	# Небольшое движение телепортом не считается.
	var buffer2 := SnapshotBuffer.new()
	buffer2.push(_snap(1, 0.0, 0.0, 1000), 1000)
	buffer2.sample(1000)
	buffer2.push(_snap(2, 2.0, 0.0, 1100), 1100)
	assert_false(bool(buffer2.sample(1050)["teleported"]))
