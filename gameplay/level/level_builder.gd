# Сборка уровня по плану (раздел 5): инстанцирует секции, расставляет
# чекпоинты, мобов, монеты, кооп-объекты и финиш из LevelPlan. У всех
# участников забега уровень собирается из одного плана — геометрия по сети
# не передаётся; зоны для проверок хоста строит host_zones() из того же
# плана (чистая функция, без нод).
class_name LevelBuilder
extends RefCounted

const PAL: Palette = preload("res://assets/palette.tres")

## Реестр секций: id секции → скрипт-класс. Пул для планировщика — pool().
const CHUNK_SCRIPTS: Dictionary = {
	"start_area": preload("res://gameplay/level/chunks/start_area.gd"),
	"easy_cacti": preload("res://gameplay/level/chunks/easy_cacti.gd"),
	"easy_gaps": preload("res://gameplay/level/chunks/easy_gaps.gd"),
	"easy_hills": preload("res://gameplay/level/chunks/easy_hills.gd"),
	"easy_birds": preload("res://gameplay/level/chunks/easy_birds.gd"),
	"medium_spikes": preload("res://gameplay/level/chunks/medium_spikes.gd"),
	"medium_falling": preload("res://gameplay/level/chunks/medium_falling.gd"),
	"medium_movers": preload("res://gameplay/level/chunks/medium_movers.gd"),
	"medium_cavern": preload("res://gameplay/level/chunks/medium_cavern.gd"),
	"coop_ledge": preload("res://gameplay/level/chunks/coop_ledge.gd"),
	"coop_gate": preload("res://gameplay/level/chunks/coop_gate.gd"),
	"coop_tower": preload("res://gameplay/level/chunks/coop_tower.gd"),
	"coop_bridge": preload("res://gameplay/level/chunks/coop_bridge.gd"),
	"bonus_coins": preload("res://gameplay/level/chunks/bonus_coins.gd"),
	"bonus_golden": preload("res://gameplay/level/chunks/bonus_golden.gd"),
	"finish_area": preload("res://gameplay/level/chunks/finish_area.gd"),
}

## Реестр мобов: kind спавна → класс.
const MOB_SCRIPTS: Dictionary = {
	"bird": preload("res://gameplay/mobs/bird.gd"),
	"critter": preload("res://gameplay/mobs/critter.gd"),
	"golden": preload("res://gameplay/mobs/golden.gd"),
}

static var _pool_cache: Array[ChunkDef] = []


## Пул секций для планировщика: метаданные всех секций проекта.
static func pool() -> Array[ChunkDef]:
	if _pool_cache.is_empty():
		for id: String in CHUNK_SCRIPTS:
			_pool_cache.append(CHUNK_SCRIPTS[id].def())
	return _pool_cache


## Собрать уровень по плану; возвращает корневую ноду (координаты мира).
static func build(plan: LevelPlan) -> Node2D:
	var root := Node2D.new()
	root.name = "Level"
	root.add_child(_sky(plan.total_width))

	var defs := {}
	for def: ChunkDef in pool():
		defs[def.id] = def

	for entry: Dictionary in plan.entries:
		var script: GDScript = CHUNK_SCRIPTS[entry["id"]]
		var chunk: Chunk = script.new()
		chunk.setup(defs[entry["id"]], entry["offset_x"])
		chunk.build()
		root.add_child(chunk)

	for cp: Dictionary in plan.checkpoints:
		var marker := CheckpointArea.new()
		marker.setup(cp["index"])
		marker.position = Vector2(cp["x"], cp["y"])
		root.add_child(marker)

	for spawn: Dictionary in plan.mob_spawns:
		var mob: Mob = MOB_SCRIPTS[spawn["kind"]].new()
		mob.setup(spawn["spawn_id"], spawn["params"])
		mob.position = Vector2(spawn["x"], spawn["y"])
		root.add_child(mob)

	for spawn: Dictionary in plan.coin_spawns:
		var coin := Coin.new()
		coin.setup(spawn["spawn_id"])
		coin.position = Vector2(spawn["x"], spawn["y"])
		root.add_child(coin)

	for spawn: Dictionary in plan.coop_spawns:
		root.add_child(_build_coop(spawn))

	for spawn: Dictionary in plan.platform_spawns:
		var platform := FallingPlatform.new()
		platform.setup(spawn["spawn_id"], Vector2(spawn["width"], 20.0))
		platform.position = Vector2(spawn["cx"], spawn["top_y"] + 10.0)
		root.add_child(platform)

	if plan.finish_x >= 0.0:
		var finish := FinishArea.new()
		finish.position = Vector2(plan.finish_x, Chunk.FLOOR_Y)
		root.add_child(finish)

	# Стены по краям уровня, чтобы не убежать за границы.
	root.add_child(_wall(-16.0))
	root.add_child(_wall(plan.total_width + 16.0))
	return root


## Зоны кооп-объектов и платформ для логики хоста (разделы 6, 7.2, 7.3):
## чистая функция плана — одинаковые прямоугольники у всех участников.
static func host_zones(plan: LevelPlan) -> Dictionary:
	var coop: Array[Dictionary] = []
	var platforms: Array[Dictionary] = []
	for spawn: Dictionary in plan.coop_spawns:
		if spawn["kind"] == "gate":
			var plates: Array[Rect2] = []
			for x: float in spawn["plates"]:
				plates.append(_plate_zone(x))
			coop.append(CoopDirector.make_gate(
				spawn["spawn_id"], plates, _ground_zone(spawn["zone_from"], spawn["zone_to"]),
				spawn["min_players"]
			))
		else:
			coop.append(CoopDirector.make_ledge(
				spawn["spawn_id"],
				_ground_zone(spawn["zone_from"], spawn["zone_to"]),
				Rect2(spawn["top_from"], spawn["top_y"] - 130.0, spawn["top_to"] - spawn["top_from"], 120.0)
			))
	for spawn: Dictionary in plan.platform_spawns:
		platforms.append({
			"id": spawn["spawn_id"],
			"zone": Rect2(
				spawn["cx"] - spawn["width"] * 0.5 - 8.0,
				spawn["top_y"] - 16.0,
				spawn["width"] + 16.0,
				24.0
			),
		})
	return {"coop": coop, "platforms": platforms}


## Зона плиты: накрывает игрока, стоящего на ней (центр тела у пола).
static func _plate_zone(x: float) -> Rect2:
	return Rect2(
		x - PressurePlate.WIDTH * 0.5 - 8.0,
		Chunk.FLOOR_Y - 60.0,
		PressurePlate.WIDTH + 16.0,
		48.0
	)


## Наземная зона (у ворот, у уступа): игрок на земле или в низком прыжке.
static func _ground_zone(from_x: float, to_x: float) -> Rect2:
	return Rect2(from_x, Chunk.FLOOR_Y - 220.0, to_x - from_x, 220.0)


## Ноды кооп-объекта по спавну из плана.
static func _build_coop(spawn: Dictionary) -> Node:
	var root := Node2D.new()
	if spawn["kind"] == "gate":
		for x: float in spawn["plates"]:
			var plate := PressurePlate.new()
			plate.position = Vector2(x, Chunk.FLOOR_Y)
			root.add_child(plate)
		var gate := CoopGate.new()
		gate.setup(spawn["spawn_id"], 64.0, Chunk.FLOOR_Y)
		gate.position = Vector2(spawn["gate_x"], Chunk.FLOOR_Y)
		root.add_child(gate)
		return root
	var ladder := RopeLadder.new()
	ladder.setup(spawn["spawn_id"], spawn["top_y"], Chunk.FLOOR_Y)
	ladder.position = Vector2(spawn["ladder_x"], 0.0)
	root.add_child(ladder)
	var fallback := FallbackPlatform.new()
	fallback.setup(spawn["spawn_id"], 128.0)
	fallback.position = Vector2(spawn["fallback_x"], spawn["fallback_top_y"] + 10.0)
	root.add_child(fallback)
	return root


## Градиентное небо на весь уровень (vertex_colors у Polygon2D).
static func _sky(width: int) -> Polygon2D:
	var sky := Polygon2D.new()
	sky.polygon = PackedVector2Array([
		Vector2(0, 0),
		Vector2(width, 0),
		Vector2(width, Chunk.ZONE_HEIGHT),
		Vector2(0, Chunk.ZONE_HEIGHT),
	])
	sky.vertex_colors = PackedColorArray([
		PAL.sky_top, PAL.sky_top, PAL.sky_bottom, PAL.sky_bottom,
	])
	sky.z_index = -10
	return sky


## Тонкая невидимая стена высотой с уровень.
static func _wall(x: float) -> StaticBody2D:
	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(32, 1024)
	shape.shape = box
	shape.position = Vector2(0, 256)
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_child(shape)
	body.position.x = x
	return body
