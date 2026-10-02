# Обязательный тест раздела 18: упаковка и распаковка 3D-снапшота без потерь
# (кроме допустимого округления скоростей до сотых м/с и поворота до ~0.0006
# рад) + бюджет размера из раздела 10 («около 26 байт»).
extends GutTest

const EPS: float = 0.001


func test_pack_unpack_lossless() -> void:
	# Координаты float32: значения, точно представимые в двоичной дроби.
	var data := Snapshot.pack(
		1234, 123.5, -678.25, 9.5, 1.25,
		6.5, -30.25, 100.0, Protocol.AnimState.RUN, 15
	)
	var snap := Snapshot.unpack(data)
	assert_eq(int(snap["seq"]), 1234)
	assert_almost_eq(float(snap["x"]), 123.5, EPS)
	assert_almost_eq(float(snap["y"]), -678.25, EPS)
	assert_almost_eq(float(snap["z"]), 9.5, EPS)
	assert_almost_eq(float(snap["yaw"]), 1.25, 0.001)
	assert_almost_eq(float(snap["vx"]), 6.5, EPS)
	assert_almost_eq(float(snap["vy"]), -30.25, EPS)
	assert_almost_eq(float(snap["vz"]), 100.0, EPS)
	assert_eq(int(snap["anim"]), Protocol.AnimState.RUN)
	assert_eq(int(snap["flags"]), 15)


func test_speed_rounding_within_tolerance() -> void:
	# Допустимая потеря — только сотые доли м/с (раздел 18).
	var data := Snapshot.pack(1, 0.0, 0.0, 0.0, 0.0, 2.607, -4.132, 0.049, 0, 0)
	var snap := Snapshot.unpack(data)
	assert_almost_eq(float(snap["vx"]), 2.607, 0.005)
	assert_almost_eq(float(snap["vy"]), -4.132, 0.005)
	assert_almost_eq(float(snap["vz"]), 0.049, 0.005)


func test_speed_clamped_to_int16() -> void:
	# Скорости хранятся как м/с × 100 в int16: предел ±327.67.
	var snap := Snapshot.unpack(Snapshot.pack(1, 0.0, 0.0, 0.0, 0.0, 400.0, -400.0, 0.0, 0, 0))
	assert_almost_eq(float(snap["vx"]), 327.67, 0.005)
	assert_almost_eq(float(snap["vy"]), -327.68, 0.005)


func test_yaw_precision_and_wrap() -> void:
	# Поворот — int16 «угол × 10000 / π» (раздел 10): шаг около 0.0006 рад,
	# ±π представимы точно.
	for yaw: float in [-PI, -PI / 2.0, 0.0, PI / 2.0, PI]:
		var snap := Snapshot.unpack(Snapshot.pack(0, 0.0, 0.0, 0.0, yaw, 0.0, 0.0, 0.0, 0, 0))
		assert_almost_eq(float(snap["yaw"]), yaw, 0.0007, "yaw %.4f" % yaw)


func test_seq_wraps_uint16() -> void:
	# seq живёт в uint16 и заворачивается после 65535.
	assert_eq(int(Snapshot.unpack(Snapshot.pack(65535, 0, 0, 0, 0, 0, 0, 0, 0, 0))["seq"]), 65535)
	assert_eq(int(Snapshot.unpack(Snapshot.pack(65536 + 4, 0, 0, 0, 0, 0, 0, 0, 0, 0))["seq"]), 4)


func test_size_within_budget() -> void:
	assert_eq(Snapshot.packed_size(), 24)
	assert_true(Snapshot.packed_size() <= Protocol.SNAPSHOT_MAX_BYTES)
	var data := Snapshot.pack(65535, 123.5, -678.25, 9.5, 1.0, 300.0, -300.0, 300.0, 5, 15)
	assert_eq(data.size(), Snapshot.packed_size())


func test_all_flags_and_anim_states_fit() -> void:
	# Все флаги раздела 10 и состояния аниматора раздела 5 укладываются в uint8.
	var all_flags: int = Protocol.FLAG_ON_FLOOR | Protocol.FLAG_HANGING \
		| Protocol.FLAG_TALKING | Protocol.FLAG_SITTING | Protocol.FLAG_HAND_HELD \
		| Protocol.FLAG_LED_BY_HAND
	assert_true(all_flags <= 255)
	for state: int in [
		Protocol.AnimState.IDLE, Protocol.AnimState.WALK, Protocol.AnimState.RUN,
		Protocol.AnimState.JUMP, Protocol.AnimState.FALL, Protocol.AnimState.LAND,
		Protocol.AnimState.BONK, Protocol.AnimState.HANG, Protocol.AnimState.PULLED_UP,
		Protocol.AnimState.HELP_PULL, Protocol.AnimState.SIT, Protocol.AnimState.HOLD_HAND,
		Protocol.AnimState.WAVE, Protocol.AnimState.EMOTE_1, Protocol.AnimState.EMOTE_6,
	]:
		var snap := Snapshot.unpack(Snapshot.pack(0, 0, 0, 0, 0, 0, 0, 0, state, all_flags))
		assert_eq(int(snap["anim"]), state)
	assert_eq(int(Snapshot.unpack(Snapshot.pack(0, 0, 0, 0, 0, 0, 0, 0, 0, all_flags))["flags"]), all_flags)
