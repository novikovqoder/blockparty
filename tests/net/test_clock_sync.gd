# Синхронизация часов с хостом (раздел 8): смещение = время хоста + RTT/2 −
# локальное время, сглаживание скользящим средним по последним 8 замерам.
extends GutTest

const EPS: float = 0.001


func test_offset_exact_under_constant_delay() -> void:
	# Хост опережает клиента на 5000 мс, RTT 80 мс (симметричный путь):
	# ping ушёл в 1000, хост ответил в 1000+5000+40, pong пришёл в 1080.
	var clock := ClockSync.new()
	clock.add_sample(1000 + 5000 + 40, 1080, 80)
	assert_almost_eq(clock.offset_msec(), 5000.0, EPS)


func test_smoothing_keeps_last_eight_samples() -> void:
	var clock := ClockSync.new()
	for i: int in range(1, 10):
		# rtt = 0: смещение замера = host_msec − local_recv = i*2000 − 1000,
		# то есть 1000, 3000, …, 17000 (девять замеров).
		clock.add_sample(i * 2000, 1000, 0)
	# Последние 8 замеров: 3000..17000, среднее 10000 (первый вытеснен).
	assert_almost_eq(clock.offset_msec(), 10000.0, EPS)


func test_last_rtt_reported() -> void:
	var clock := ClockSync.new()
	assert_eq(clock.last_rtt_msec(), -1)
	clock.add_sample(5000, 4000, 123)
	clock.add_sample(6000, 5000, 77)
	assert_eq(clock.last_rtt_msec(), 77)


func test_clear_resets_history() -> void:
	var clock := ClockSync.new()
	clock.add_sample(9000, 1000, 0)
	clock.clear()
	assert_almost_eq(clock.offset_msec(), 0.0, EPS)
	assert_eq(clock.last_rtt_msec(), -1)
