# Буфер снапшотов (раздел 8): отбрасывание старых seq с учётом wrap uint16,
# линейная интерполяция с задержкой, лимит экстраполяции и телепорт дальше
# 256 px без сглаживания.
extends GutTest

const EPS: float = 0.01


func _snap(seq: int, x: float, vx: float, t: int) -> Dictionary:
	return {"seq": seq, "x": x, "y": 0.0, "vx": vx, "vy": 0.0, "anim": 0, "flags": 0, "t": t}


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


func test_extrapolation_limited_then_frozen() -> void:
	var buffer := SnapshotBuffer.new()
	buffer.push(_snap(1, 0.0, 200.0, 1000), 1000)
	# 75 мс вперёд — экстраполяция скоростью: 0 + 200 * 0.075 = 15.
	var ahead: Dictionary = buffer.sample(1075)
	assert_almost_eq(float(ahead["x"]), 15.0, 0.1)
	assert_false(bool(ahead["frozen"]))
	# Ровно на лимите 150 мс — ещё экстраполяция: 200 * 0.150 = 30.
	var at_limit: Dictionary = buffer.sample(1150)
	assert_almost_eq(float(at_limit["x"]), 30.0, 0.1)
	assert_false(bool(at_limit["frozen"]))
	# Дальше лимита — персонаж замирает и больше не двигается.
	var far: Dictionary = buffer.sample(1300)
	assert_true(bool(far["frozen"]))
	assert_almost_eq(float(far["x"]), 30.0, EPS)
	assert_almost_eq(float(buffer.sample(2000)["x"]), 30.0, EPS)


func test_teleport_beyond_256_px() -> void:
	var buffer := SnapshotBuffer.new()
	buffer.push(_snap(1, 0.0, 0.0, 1000), 1000)
	buffer.sample(1000)  # отрисовались в 0
	buffer.push(_snap(2, 1000.0, 0.0, 1100), 1100)
	var jump: Dictionary = buffer.sample(1050)
	assert_true(bool(jump["teleported"]), "скачок 500 px — телепорт")
	# Небольшое движение телепортом не считается.
	var buffer2 := SnapshotBuffer.new()
	buffer2.push(_snap(1, 0.0, 0.0, 1000), 1000)
	buffer2.sample(1000)
	buffer2.push(_snap(2, 200.0, 0.0, 1100), 1100)
	assert_false(bool(buffer2.sample(1050)["teleported"]))
