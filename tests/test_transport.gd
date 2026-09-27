# Эмуляция плохой сети в EnetTransport (раздел 16, аргументы --net-lag /
# --net-loss) и константы протокола (раздел 8). --net-lag трактуется как RTT:
# каждая отправка задерживается на половину с джиттером.
extends GutTest


func test_delay_zero_without_lag() -> void:
	assert_eq(EnetTransport.compute_delay_ms(0, 0.5), 0)


func test_delay_bounds_lag_as_rtt_with_jitter() -> void:
	# Половина 150 = 75, джиттер 20% от неё = 15: диапазон [60, 90].
	assert_eq(EnetTransport.compute_delay_ms(150, 0.0), 60)
	assert_eq(EnetTransport.compute_delay_ms(150, 0.5), 75)
	assert_eq(EnetTransport.compute_delay_ms(150, 1.0), 90)


func test_loss_threshold() -> void:
	assert_true(EnetTransport._is_dropped(5, 0.04), "roll 4% при потере 5% — потерян")
	assert_false(EnetTransport._is_dropped(5, 0.06), "roll 6% при потере 5% — доставлен")
	assert_false(EnetTransport._is_dropped(0, 0.0), "без потерь ничего не теряется")


func test_protocol_constants_section8() -> void:
	assert_true(Protocol.PROTOCOL_VERSION >= 1)
	assert_eq(Protocol.MAX_PLAYERS, 12)
	assert_eq(Protocol.MAX_PLAYERS_HARD, 16)
	assert_eq(Protocol.MIN_PLAYERS_TO_START, 2)
	# Каналы 0..2 из раздела 8, все разные.
	assert_eq(Protocol.CHANNEL_RELIABLE, 0)
	assert_eq(Protocol.CHANNEL_SNAPSHOT, 1)
	assert_eq(Protocol.CHANNEL_VOICE, 2)
	assert_eq(Protocol.SNAPSHOT_HZ, 20.0)
	assert_eq(Protocol.INTERP_DELAY_MS, 100)
	assert_eq(Protocol.EXTRAPOLATION_MS, 150)
	assert_eq(Protocol.TELEPORT_DISTANCE, 256.0)
	assert_eq(Protocol.START_READY_TIMEOUT, 15.0)
	assert_eq(Protocol.GO_DELAY, 3.0)
