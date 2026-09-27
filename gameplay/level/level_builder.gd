# Сборка уровня по плану (раздел 5): инстанцирует секции, расставляет
# чекпоинты, мобов, монеты и финиш из LevelPlan. У всех участников забега
# уровень собирается из одного плана — геометрия по сети не передаётся.
class_name LevelBuilder
extends RefCounted

const PAL: Palette = preload("res://assets/palette.tres")

## Реестр секций: id секции → скрипт-класс. Пул для планировщика — pool().
const CHUNK_SCRIPTS: Dictionary = {
	"start_area": preload("res://gameplay/level/chunks/start_area.gd"),
	"easy_cacti": preload("res://gameplay/level/chunks/easy_cacti.gd"),
	"medium_spikes": preload("res://gameplay/level/chunks/medium_spikes.gd"),
	"coop_ledge": preload("res://gameplay/level/chunks/coop_ledge.gd"),
	"bonus_coins": preload("res://gameplay/level/chunks/bonus_coins.gd"),
	"finish_area": preload("res://gameplay/level/chunks/finish_area.gd"),
}

## Реестр мобов: kind спавна → класс.
const MOB_SCRIPTS: Dictionary = {
	"bird": preload("res://gameplay/mobs/bird.gd"),
	"critter": preload("res://gameplay/mobs/critter.gd"),
}

static var _pool_cache: Array[ChunkDef] = []


## Пул секций для планировщика: метаданные всех секций проекта.
static func pool() -> Array[ChunkDef]:
	if _pool_cache.is_empty():
		for id: String in CHUNK_SCRIPTS:
			_pool_cache.append(CHUNK_SCRIPTS[id].def())
	return _pool_cache


## Собрать уровень плану; возвращает корневую ноду (координаты мира).
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

	if plan.finish_x >= 0.0:
		var finish := FinishArea.new()
		finish.position = Vector2(plan.finish_x, Chunk.FLOOR_Y)
		root.add_child(finish)

	# Стены по краям уровня, чтобы не убежать за границы.
	root.add_child(_wall(-16.0))
	root.add_child(_wall(plan.total_width + 16.0))
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
