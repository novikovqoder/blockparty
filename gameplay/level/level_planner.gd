# Планировщик забега по seed (раздел 5 SPEC). Выбирает секции из пула
# правилами: каждая 3-я — кооперативная, соседние не повторяются, секция
# не встречается дважды (при достаточном пуле). Использует только
# RandomNumberGenerator с заданным seed — никакого randi()/randf().
class_name LevelPlanner
extends RefCounted

const COOP_STRIDE: int = 3  # каждая 3-я секция — кооп-ворота (раздел 5)


## Построить план забега: start + section_count секций + finish.
static func plan(seed: int, pool: Array[ChunkDef], section_count: int) -> LevelPlan:
	var plan := LevelPlan.new()
	plan.seed_value = seed
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var defs := _pick_chunks(rng, pool, section_count)
	var start := _find_type(pool, ChunkDef.Type.START)
	var finish := _find_type(pool, ChunkDef.Type.FINISH)
	# Стартовая и финишная площадки фиксированы (раздел 5).
	defs.push_front(start)
	defs.push_back(finish)

	var offset_x := 0.0
	var section_index := 0
	var next_spawn_id := 0
	for def: ChunkDef in defs:
		plan.entries.append({
			"id": def.id,
			"type": def.type,
			"offset_x": offset_x,
			"width": def.width,
		})
		if def.type == ChunkDef.Type.START:
			plan.spawn_point = Vector2(offset_x + def.checkpoint.x, def.checkpoint.y - 32.0)
		if def.type == ChunkDef.Type.FINISH and def.finish_x >= 0.0:
			plan.finish_x = offset_x + def.finish_x
		# Чекпоинт в начале каждой секции, кроме стартовой площадки.
		if def.type != ChunkDef.Type.START:
			section_index += 1
			plan.checkpoints.append({
				"index": section_index,
				"x": offset_x + def.checkpoint.x,
				"y": def.checkpoint.y - 32.0,
			})
		for mob: Dictionary in def.mob_spawns:
			plan.mob_spawns.append({
				"spawn_id": next_spawn_id,
				"kind": mob["kind"],
				"x": offset_x + mob["x"],
				"y": mob["y"],
				"params": mob.get("params", {}),
			})
			next_spawn_id += 1
		for coin: Vector2 in def.coin_spawns:
			plan.coin_spawns.append({
				"spawn_id": next_spawn_id,
				"x": offset_x + coin.x,
				"y": coin.y,
			})
			next_spawn_id += 1
		for hp: float in def.hang_points:
			plan.hang_points.append(Vector2(offset_x + hp, 576.0))
		offset_x += def.width
	plan.total_width = int(offset_x)
	return plan


## Выбор игровых секций: кооп на позициях 3, 6, … (1-based), остальное —
## перемешанный пул без повторов и соседних дублей.
static func _pick_chunks(rng: RandomNumberGenerator, pool: Array[ChunkDef], count: int) -> Array[ChunkDef]:
	var coops: Array[ChunkDef] = []
	var others: Array[ChunkDef] = []
	for def: ChunkDef in pool:
		if def.type == ChunkDef.Type.START or def.type == ChunkDef.Type.FINISH:
			continue
		if def.is_coop():
			coops.append(def)
		else:
			others.append(def)

	_shuffle(rng, coops)
	_shuffle(rng, others)

	var coop_i := 0
	var other_i := 0
	var picked: Array[ChunkDef] = []
	for pos: int in count:
		var is_coop_pos: bool = (pos + 1) % COOP_STRIDE == 0
		if is_coop_pos and not coops.is_empty():
			# На нехватку кооп-секций: берём по кругу, не допуская соседних дублей.
			var chunk := coops[coop_i % coops.size()]
			if picked.size() > 0 and picked[-1].id == chunk.id and coops.size() > 1:
				coop_i += 1
				chunk = coops[coop_i % coops.size()]
			coop_i += 1
			picked.append(chunk)
		else:
			var chunk := others[other_i % others.size()]
			if picked.size() > 0 and picked[-1].id == chunk.id and others.size() > 1:
				other_i += 1
				chunk = others[other_i % others.size()]
			other_i += 1
			picked.append(chunk)
	return picked


## Fisher–Yates shuffle на заданном генераторе — источник детерминизма.
static func _shuffle(rng: RandomNumberGenerator, items: Array[ChunkDef]) -> void:
	for i: int in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: ChunkDef = items[i]
		items[i] = items[j]
		items[j] = tmp


static func _find_type(pool: Array[ChunkDef], type: int) -> ChunkDef:
	for def: ChunkDef in pool:
		if def.type == type:
			return def
	push_error("LevelPlanner: в пуле нет секции типа %d" % type)
	return ChunkDef.new()
