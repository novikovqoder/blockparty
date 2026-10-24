# Обязательный тест раздела 18 «AOI-фильтр»: частота снапшотов по дистанции
# (раздел 10: до 60 м — 20 Гц, 60–150 м — 4 Гц, дальше — 1 Гц для карты),
# гейтинг по времени и бюджет трафика при 12 игроках.
extends GutTest

const EPS: float = 0.001


func test_rate_by_distance() -> void:
	assert_almost_eq(AoiFilter.rate_hz(0.0), 20.0, EPS, "рядом — полная частота")
	assert_almost_eq(AoiFilter.rate_hz(59.9), 20.0, EPS, "почти 60 м — полная")
	assert_almost_eq(AoiFilter.rate_hz(60.0), 20.0, EPS, "ровно 60 м — ещё полная")
	assert_almost_eq(AoiFilter.rate_hz(60.1), 4.0, EPS, "за 60 м — редкие")
	assert_almost_eq(AoiFilter.rate_hz(150.0), 4.0, EPS, "ровно 150 м — ещё редкие")
	assert_almost_eq(AoiFilter.rate_hz(150.1), 1.0, EPS, "за 150 м — только карта")


func test_gating_full_rate() -> void:
	# 20 Гц: снапшот не чаще раза в 50 мс.
	var filter := AoiFilter.new()
	assert_true(filter.allow(1, 2, 10.0, 1000), "первый — всегда")
	assert_false(filter.allow(1, 2, 10.0, 1030), "30 мс спустя — рано")
	assert_true(filter.allow(1, 2, 10.0, 1051), "51 мс спустя — можно")


func test_gating_far_rate() -> void:
	# 1 Гц: не чаще раза в секунду.
	var filter := AoiFilter.new()
	assert_true(filter.allow(1, 2, 200.0, 5000))
	assert_false(filter.allow(1, 2, 200.0, 5900))
	assert_true(filter.allow(1, 2, 200.0, 6000))


func test_pairs_are_independent() -> void:
	# Пауза своя для каждой пары «отправитель → получатель».
	var filter := AoiFilter.new()
	assert_true(filter.allow(1, 2, 10.0, 1000))
	assert_false(filter.allow(1, 2, 10.0, 1010), "та же пара — рано")
	assert_true(filter.allow(2, 1, 10.0, 1010), "обратное направление — можно")
	assert_true(filter.allow(1, 3, 10.0, 1010), "другой получатель — можно")


func test_distance_change_updates_rate() -> void:
	# Игроки разошлись: следующая пересылка по новой (большей) паузе
	# (последняя была на t=50, дальняя пауза — 250 мс, значит не раньше t=300).
	var filter := AoiFilter.new()
	assert_true(filter.allow(1, 2, 10.0, 0))
	assert_true(filter.allow(1, 2, 10.0, 50), "рядом — каждые 50 мс")
	assert_false(filter.allow(1, 2, 120.0, 299), "далеко — раньше 250 мс от последней нельзя")
	assert_true(filter.allow(1, 2, 120.0, 300))


func test_clear_resets_history() -> void:
	var filter := AoiFilter.new()
	assert_true(filter.allow(1, 2, 10.0, 1000))
	assert_false(filter.allow(1, 2, 10.0, 1010), "без clear() — рано")
	filter.clear()
	assert_true(filter.allow(1, 2, 10.0, 1010), "после clear() история забыта")


func test_traffic_budget_12_players() -> void:
	# Бюджет раздела 10: хост до 200 КБ/с на отдачу, клиент до 40 КБ/с на приём.
	# Худший случай AOI: все 12 игроков в радиусе 60 м друг от друга —
	# хост пересылает каждому по 11 потоков полной частоты.
	var per_snapshot: int = Snapshot.packed_size()
	var host_out_bps: int = (Protocol.MAX_PLAYERS - 1) * (Protocol.MAX_PLAYERS - 1)
	host_out_bps *= int(Protocol.AOI_RATE_FULL_HZ) * per_snapshot
	var client_in_bps: int = (Protocol.MAX_PLAYERS - 1) * int(Protocol.AOI_RATE_FULL_HZ)
	client_in_bps *= per_snapshot
	assert_lt(host_out_bps, 200 * 1024, "отдача хоста в бюджете 200 КБ/с")
	assert_lt(client_in_bps, 40 * 1024, "приём клиента в бюджете 40 КБ/с")


func test_aoi_reduces_worst_case() -> void:
	# Половина игроков за 150 м: каждому дальнему — 1 Гц вместо 20.
	var full: int = 6 * int(Protocol.AOI_RATE_FULL_HZ) * Snapshot.packed_size()
	var far: int = 5 * int(Protocol.AOI_RATE_FAR_HZ) * Snapshot.packed_size()
	assert_lt(full + far, 11 * int(Protocol.AOI_RATE_FULL_HZ) * Snapshot.packed_size(),
		"AOI сокращает поток дальним игрокам")
