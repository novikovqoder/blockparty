# План забега — результат работы LevelPlanner по seed (раздел 5 SPEC): список
# секций с мировыми смещениями, спавны мобов и монет с уникальными spawn_id,
# чекпоинты, точки зацепа и финиш. Чистые данные: одинаковый seed даёт
# побитово одинаковый план (проверяется хешем в тестах GUT).
class_name LevelPlan
extends RefCounted

var seed_value: int = 0
## Записи секций: {id: String, type: int, offset_x: float, width: int}.
var entries: Array[Dictionary] = []
## Спавны мобов в мировых координатах: {spawn_id, kind, x, y, params}.
var mob_spawns: Array[Dictionary] = []
## Спавны монет в мировых координатах: {spawn_id, x, y}.
var coin_spawns: Array[Dictionary] = []
## Кооп-объекты в мировых координатах (разделы 7.2, 7.3): поля ChunkDef.coop_spawns
## плюс spawn_id и offset_x, добавленные к каждой координате.
var coop_spawns: Array[Dictionary] = []
## Падающие платформы в мировых координатах: {spawn_id, cx, top_y, width}.
var platform_spawns: Array[Dictionary] = []
## Чекпоинты: {index, x, y} — по одному на начало каждой игровой секции.
var checkpoints: Array[Dictionary] = []
## Мировые точки зацепа у краёв пропастей.
var hang_points: Array[Vector2] = []
## Точка появления игрока на стартовой площадке.
var spawn_point: Vector2 = Vector2.ZERO
## Мировая x-координата финишной черты (-1 — нет).
var finish_x: float = -1.0
## Полная ширина уровня, px (для камеры и стен).
var total_width: int = 0


## Каноническая строка плана — фиксирует каждую его деталь.
func canonical() -> String:
	var parts: Array[String] = ["seed=%d" % seed_value]
	for e: Dictionary in entries:
		parts.append("e:%s:%d:%d" % [e["id"], int(e["offset_x"]), e["width"]])
	for m: Dictionary in mob_spawns:
		parts.append("m:%d:%s:%d:%d:%s" % [m["spawn_id"], m["kind"], int(m["x"]), int(m["y"]), JSON.stringify(m["params"])])
	for c: Dictionary in coin_spawns:
		parts.append("c:%d:%d:%d" % [c["spawn_id"], int(c["x"]), int(c["y"])])
	for co: Dictionary in coop_spawns:
		if co["kind"] == "gate":
			parts.append("co:%d:gate:%d:%s:%d:%d:%d" % [
				co["spawn_id"], int(co["gate_x"]), JSON.stringify(co["plates"]),
				int(co["zone_from"]), int(co["zone_to"]), int(co["min_players"]),
			])
		else:
			parts.append("co:%d:ledge:%d:%d:%d:%d:%d:%d:%d:%d" % [
				co["spawn_id"], int(co["ladder_x"]), int(co["top_y"]),
				int(co["fallback_x"]), int(co["fallback_top_y"]),
				int(co["zone_from"]), int(co["zone_to"]),
				int(co["top_from"]), int(co["top_to"]),
			])
	for pl: Dictionary in platform_spawns:
		parts.append("pl:%d:%d:%d:%d" % [pl["spawn_id"], int(pl["cx"]), int(pl["top_y"]), int(pl["width"])])
	for cp: Dictionary in checkpoints:
		parts.append("cp:%d:%d:%d" % [cp["index"], int(cp["x"]), int(cp["y"])])
	for hp: Vector2 in hang_points:
		parts.append("hp:%d:%d" % [int(hp.x), int(hp.y)])
	parts.append("sp:%d:%d" % [int(spawn_point.x), int(spawn_point.y)])
	parts.append("fin:%d" % int(finish_x))
	parts.append("w:%d" % total_width)
	return "\n".join(parts)


## Хеш плана для теста детерминизма (раздел 5: 1000 seed, два прогона).
func plan_hash() -> int:
	return canonical().hash()
