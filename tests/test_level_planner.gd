# Тест планировщика уровня (gameplay/level/level_planner.gd).
# Обязательное требование раздела 16 SPEC: детерминизм генератора —
# 1000 seed, два прогона, сравнение хешей списка секций и спавнов.
extends GutTest

const SEEDS_TO_TEST: int = 1000


func test_determinism_1000_seeds() -> void:
	var pool := LevelBuilder.pool()
	for seed_value: int in SEEDS_TO_TEST:
		var first := LevelPlanner.plan(seed_value, pool, 4)
		var second := LevelPlanner.plan(seed_value, pool, 4)
		assert_eq(first.plan_hash(), second.plan_hash(), "хеш плана seed=%d" % seed_value)
		assert_eq(first.canonical(), second.canonical(), "побитово: seed=%d" % seed_value)


func test_same_seed_same_sections_and_spawns() -> void:
	var pool := LevelBuilder.pool()
	var first := LevelPlanner.plan(42, pool, 4)
	var second := LevelPlanner.plan(42, pool, 4)
	assert_eq(first.entries, second.entries)
	assert_eq(first.mob_spawns, second.mob_spawns)
	assert_eq(first.coin_spawns, second.coin_spawns)


func test_spawn_ids_unique_and_sequential() -> void:
	var pool := LevelBuilder.pool()
	var plan := LevelPlanner.plan(7, pool, 4)
	var ids: Array[int] = []
	for mob: Dictionary in plan.mob_spawns:
		ids.append(mob["spawn_id"])
	for coin: Dictionary in plan.coin_spawns:
		ids.append(coin["spawn_id"])
	assert_eq(ids.size(), plan.mob_spawns.size() + plan.coin_spawns.size())
	# Уникальность и непрерывность нумерации.
	var unique := {}
	for id: int in ids:
		assert_false(unique.has(id), "spawn_id %d не уникален" % id)
		unique[id] = true
	ids.sort()
	for i: int in ids.size():
		assert_eq(ids[i], i, "spawn_id идут подряд от 0")


func test_sections_not_repeated() -> void:
	# Раздел 5: одна секция не встречается в забеге больше одного раза
	# (при пуле из 4 секций и 4 местах это перестановка).
	var pool := LevelBuilder.pool()
	var plan := LevelPlanner.plan(99, pool, 4)
	var seen := {}
	for entry: Dictionary in plan.entries:
		var id: String = entry["id"]
		assert_false(seen.has(id), "секция %s встречается дважды" % id)
		seen[id] = true


func test_no_adjacent_duplicates() -> void:
	for seed_value: int in 200:
		var plan := LevelPlanner.plan(seed_value, LevelBuilder.pool(), 4)
		for i: int in range(1, plan.entries.size()):
			assert_ne(
				plan.entries[i]["id"], plan.entries[i - 1]["id"],
				"соседние дубли при seed=%d" % seed_value
			)


func test_every_third_section_is_coop() -> void:
	# Раздел 5: каждая 3-я секция (3-я и 6-я) — кооперативная.
	for seed_value: int in 100:
		var plan := LevelPlanner.plan(seed_value, LevelBuilder.pool(), 4)
		for pos: int in range(1, plan.entries.size() - 1):
			var is_coop_pos: bool = pos % LevelPlanner.COOP_STRIDE == 0  # pos — 1-based внутри
			var entry: Dictionary = plan.entries[pos]
			var is_coop: bool = entry["type"] == ChunkDef.Type.COOP
			assert_eq(is_coop, is_coop_pos, "позиция %d seed=%d" % [pos, seed_value])


func test_start_first_finish_last() -> void:
	var plan := LevelPlanner.plan(1, LevelBuilder.pool(), 4)
	assert_eq(plan.entries[0]["type"], ChunkDef.Type.START)
	assert_eq(plan.entries[plan.entries.size() - 1]["type"], ChunkDef.Type.FINISH)


func test_offsets_chain_and_width() -> void:
	var plan := LevelPlanner.plan(5, LevelBuilder.pool(), 4)
	var expected := 0.0
	for entry: Dictionary in plan.entries:
		assert_eq(entry["offset_x"], expected)
		expected += entry["width"]
	assert_eq(plan.total_width, int(expected))


func test_checkpoints_and_hang_points() -> void:
	var plan := LevelPlanner.plan(11, LevelBuilder.pool(), 4)
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
