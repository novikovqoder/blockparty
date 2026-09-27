# Обязательный тест раздела 16: упаковка и распаковка снапшота без потерь
# (кроме допустимого округления скоростей до целых px/с) + бюджет размера
# из раздела 8 («около 20 байт»).
extends GutTest

const EPS: float = 0.001


func test_pack_unpack_lossless() -> void:
	# Позиции float32: значения, точно представимые в двоичной дроби.
	var data := Snapshot.pack(1234, 12345.5, -6789.25, 260.0, -520.0, Protocol.AnimState.RUN, 15)
	var snap := Snapshot.unpack(data)
	assert_eq(int(snap["seq"]), 1234)
	assert_almost_eq(float(snap["x"]), 12345.5, EPS)
	assert_almost_eq(float(snap["y"]), -6789.25, EPS)
	assert_almost_eq(float(snap["vx"]), 260.0, EPS)
	assert_almost_eq(float(snap["vy"]), -520.0, EPS)
	assert_eq(int(snap["anim"]), Protocol.AnimState.RUN)
	assert_eq(int(snap["flags"]), 15)


func test_speed_rounding_within_tolerance() -> void:
	# Допустимая потеря — только дроби скоростей (раздел 16).
	var data := Snapshot.pack(1, 0.0, 0.0, 260.7, -413.2, 0, 0)
	var snap := Snapshot.unpack(data)
	assert_almost_eq(float(snap["vx"]), 260.7, 0.5)
	assert_almost_eq(float(snap["vy"]), -413.2, 0.5)


func test_speed_clamped_to_int16() -> void:
	var snap := Snapshot.unpack(Snapshot.pack(1, 0.0, 0.0, 40000.0, -40000.0, 0, 0))
	assert_eq(int(snap["vx"]), 32767)
	assert_eq(int(snap["vy"]), -32768)


func test_seq_wraps_uint16() -> void:
	# seq живёт в uint16 и заворачивается после 65535.
	assert_eq(int(Snapshot.unpack(Snapshot.pack(65535, 0, 0, 0, 0, 0, 0))["seq"]), 65535)
	assert_eq(int(Snapshot.unpack(Snapshot.pack(65536 + 4, 0, 0, 0, 0, 0, 0))["seq"]), 4)


func test_size_within_budget() -> void:
	assert_eq(Snapshot.packed_size(), 16)
	assert_true(Snapshot.packed_size() <= Protocol.SNAPSHOT_MAX_BYTES)
	var data := Snapshot.pack(65535, 12345.5, -6789.25, 32767, -32768, 5, 15)
	assert_eq(data.size(), Snapshot.packed_size())


func test_all_flags_and_anim_states_fit() -> void:
	# Все флаги раздела 8 и состояния аниматора укладываются в uint8.
	var all_flags: int = Protocol.FLAG_FACING_RIGHT | Protocol.FLAG_ON_FLOOR \
		| Protocol.FLAG_HANGING | Protocol.FLAG_TALKING
	assert_true(all_flags <= 255)
	for state: int in [
		Protocol.AnimState.IDLE, Protocol.AnimState.RUN, Protocol.AnimState.JUMP,
		Protocol.AnimState.FALL, Protocol.AnimState.ATTACK, Protocol.AnimState.HANG,
	]:
		var snap := Snapshot.unpack(Snapshot.pack(0, 0.0, 0.0, 0.0, 0.0, state, all_flags))
		assert_eq(int(snap["anim"]), state)
	assert_eq(int(Snapshot.unpack(Snapshot.pack(0, 0.0, 0.0, 0.0, 0.0, 0, all_flags))["flags"]), all_flags)
