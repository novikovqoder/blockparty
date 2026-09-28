# Тест планировщика уровня (gameplay/level/level_planner.gd).
# Обязательное требование раздела 16 SPEC: детерминизм генератора —
# 1000 seed, два прогона, сравнение хешей списка секций и спавнов.
# Этап 3: пул 14 секций (4+4+4+2), в забег идут 8 (balance.sections_per_run).
extends GutTest

const B: Balance = preload("res://gameplay/balance.tres")
const SEEDS_TO_TEST: int = 1000


func test_determinism_1000_seeds() -> void:
	var pool := LevelBuilder.pool()
	for seed_value: int in SEEDS_TO_TEST:
		var first := LevelPlanner.plan(seed_value, pool, B.sections_per_run)
		var second := LevelPlanner.plan(seed_value, pool, B.sections_per_run)
		assert_eq(first.plan_hash(), second.plan_hash(), "хеш плана seed=%d" % seed_value)
		assert_eq(first.canonical(), second.canonical(), "побитово: seed=%d" % seed_value)


func test_pool_has_14_sections() -> void:
	# Раздел 5: 4 лёгких, 4 средних, 4 кооп, 2 бонусных + старт и финиш.
	var counts := {}
	for def: ChunkDef in LevelBuilder.pool():
		counts[def.type] = int(counts.get(def.type, 0)) + 1
	assert_eq(int(counts.get(ChunkDef.Type.EASY, 0)), 4, "лёгких секций")
	assert_eq(int(counts.get(ChunkDef.Type.MEDIUM, 0)), 4, "средних секций")
	assert_eq(int(counts.get(ChunkDef.Type.COOP, 0)), 4, "кооп-секций")
	assert_eq(int(counts.get(ChunkDef.Type.BONUS, 0)), 2, "бонусных секций")
	assert_eq(int(counts.get(ChunkDef.Type.START, 0)), 1)
	assert_eq(int(counts.get(ChunkDef.Type.FINISH, 0)), 1)


func test_same_seed_same_sections_and_spawns() -> void:
	var pool := LevelBuilder.pool()
	var first := LevelPlanner.plan(42, pool, B.sections_per_run)
	var second := LevelPlanner.plan(42, pool, B.sections_per_run)
	assert_eq(first.entries, second.entries)
	assert_eq(first.mob_spawns, second.mob_spawns)
	assert_eq(first.coin_spawns, second.coin_spawns)
	assert_eq(first.coop_spawns, second.coop_spawns)
	assert_eq(first.platform_spawns, second.platform_spawns)


func test_spawn_ids_unique_and_sequential() -> void:
	var plan := LevelPlanner.plan(7, LevelBuilder.pool(), B.sections_per_run)
	var ids: Array[int] = []
	for mob: Dictionary in plan.mob_spawns:
		ids.append(mob["spawn_id"])
	for coin: Dictionary in plan.coin_spawns:
		ids.append(coin["spawn_id"])
	for co: Dictionary in plan.coop_spawns:
		ids.append(co["spawn_id"])
	for pl: Dictionary in plan.platform_spawns:
		ids.append(pl["spawn_id"])
	assert_eq(ids.size(), plan.mob_spawns.size() + plan.coin_spawns.size() + plan.coop_spawns.size() + plan.platform_spawns.size())
	# Уникальность и непрерывность нумерации (включая кооп-объекты и платформы).
	var unique := {}
	for id: int in ids:
		assert_false(unique.has(id), "spawn_id %d не уникален" % id)
		unique[id] = true
	ids.sort()
	for i: int in ids.size():
		assert_eq(ids[i], i, "spawn_id идут подряд от 0")


func test_coop_spawns_world_coordinates() -> void:
	# Кооп-объекты переводятся в мировые координаты: x сдвигается на offset_x
	# секции, высоты остаются локальными.
	var found_gate := false
	var found_ledge := false
	for seed_value: int in 50:
		var plan := LevelPlanner.plan(seed_value, LevelBuilder.pool(), B.sections_per_run)
		for co: Dictionary in plan.coop_spawns:
			assert_true(co.has("spawn_id"))
			assert_true(co["zone_from"] < co["zone_to"])
			assert_true(co["zone_from"] >= 0.0, "зона смещена в мир")
			if co["kind"] == "gate":
				found_gate = true
				assert_true((co["plates"] as Array).size() >= 1, "у ворот есть плиты")
				assert_true(co["gate_x"] > co["zone_from"], "ворота за зоной таймера")
			else:
				found_ledge = true
				assert_true(co["top_from"] < co["top_to"])
	assert_true(found_gate, "в пуле есть ворота")
	assert_true(found_ledge, "в пуле есть уступ")


func test_sections_not_repeated() -> void:
	# Раздел 5: одна секция не встречается в забеге больше одного раза
	# (8 мест и пул 12 некооп-вариантов — без повторов).
	var pool := LevelBuilder.pool()
	var plan := LevelPlanner.plan(99, pool, B.sections_per_run)
	var seen := {}
	for entry: Dictionary in plan.entries:
		var id: String = entry["id"]
		assert_false(seen.has(id), "секция %s встречается дважды" % id)
		seen[id] = true


func test_no_adjacent_duplicates() -> void:
	for seed_value: int in 200:
		var plan := LevelPlanner.plan(seed_value, LevelBuilder.pool(), B.sections_per_run)
		for i: int in range(1, plan.entries.size()):
			assert_ne(
				plan.entries[i]["id"], plan.entries[i - 1]["id"],
				"соседние дубли при seed=%d" % seed_value
			)


func test_every_third_section_is_coop() -> void:
	# Раздел 5: каждая 3-я секция (3-я и 6-я) — кооперативная.
	for seed_value: int in 100:
		var plan := LevelPlanner.plan(seed_value, LevelBuilder.pool(), B.sections_per_run)
		for pos: int in range(1, plan.entries.size() - 1):
			var is_coop_pos: bool = pos % LevelPlanner.COOP_STRIDE == 0  # pos — 1-based внутри
			var entry: Dictionary = plan.entries[pos]
			var is_coop: bool = entry["type"] == ChunkDef.Type.COOP
			assert_eq(is_coop, is_coop_pos, "позиция %d seed=%d" % [pos, seed_value])


func test_start_first_finish_last() -> void:
	var plan := LevelPlanner.plan(1, LevelBuilder.pool(), B.sections_per_run)
	assert_eq(plan.entries[0]["type"], ChunkDef.Type.START)
	assert_eq(plan.entries[plan.entries.size() - 1]["type"], ChunkDef.Type.FINISH)
	assert_eq(plan.entries.size(), B.sections_per_run + 2)


func test_offsets_chain_and_width() -> void:
	var plan := LevelPlanner.plan(5, LevelBuilder.pool(), B.sections_per_run)
	var expected := 0.0
	for entry: Dictionary in plan.entries:
		assert_eq(entry["offset_x"], expected)
		expected += entry["width"]
	assert_eq(plan.total_width, int(expected))


func test_checkpoints_and_hang_points() -> void:
	var plan := LevelPlanner.plan(11, LevelBuilder.pool(), B.sections_per_run)
	# По чекпоинту на начало каждой игровой секции (площадки — без чекпоинтов).
	var gameplay_sections := plan.entries.size() - 2
	assert_eq(plan.checkpoints.size(), gameplay_sections)
	for i: int in plan.checkpoints.size():
		assert_eq(plan.checkpoints[i]["index"], i + 1)
	# Все точки зацепа на уровне пола (раздел 5: y = 576).
	for hp: Vector2 in plan.hang_points:
		assert_eq(hp.y, 576.0)
	assert_true(plan.hang_points.size() > 0, "в пуле есть пропасти")
	# Точка спавна — над стартовой площадкой, финиш — внутри уровня.
	assert_almost_eq(plan.spawn_point.y, 576.0 - 32.0, 0.01)
	assert_true(plan.finish_x > 0.0 and plan.finish_x < plan.total_width)


func test_widths_are_multiples_of_64() -> void:
	for def: ChunkDef in LevelBuilder.pool():
		assert_eq(def.width % 64, 0, "ширина %s кратна 64" % def.id)
