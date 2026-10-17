# Детерминированная расстановка жителей острова (П5.9 переделка П4:
# задания жителей удалены, Финн/Луми/Тимьян остались персонажами):
# Финн у выхода к Расщелине, Луми у тропы к Холмам, Тимьян сидит
# у костра между лавками. Высоты — из запечённой карты IslandArt.
# Чистые функции: одинаковые позиции у хоста и клиентов без передачи
# по сети (узлы запекаются в island.tscn генератором острова).
class_name FolkLayout
extends RefCounted

## Жители: Финн (0) у выхода к Расщелине, Луми (1) у тропы к Холмам,
## Тимьян (2) сидит у костра между лавками (угол 0° — лавки на PI/8 + k·PI/4).
## Отступ от центра площади и от костра, м.
const PLAZA_EDGE: float = 15.0
const THYME_STUMP_DIST: float = 2.2
## Центр костра (IslandGen._campfire).
const CAMPFIRE: Vector3 = Vector3(0.5, 2.0, 2.5)


## Места жителей: {character, pos, yaw, sitting}. Все смотрят
## к центру площади; Тимьян — к костру.
static func npc_spots(art: IslandArt) -> Array[Dictionary]:
	var spots: Array[Dictionary] = []
	# Финн: у выхода с Площади в сторону Расщелины (62, 57).
	spots.append(_edge_spot(art, 0, Vector2(62.0, 57.0)))
	# Луми: у края Площади, у тропы к Холмам (-58, 42).
	spots.append(_edge_spot(art, 1, Vector2(-58.0, 42.0)))
	# Тимьян: сидит у костра между лавками, лицом к огню.
	var stump := Vector3(CAMPFIRE.x + THYME_STUMP_DIST, 0.0, CAMPFIRE.z)
	stump.y = ground_height(art, stump.x, stump.z)
	var to_fire := (CAMPFIRE - stump).normalized()
	spots.append({
		"character": 2,
		"pos": stump,
		"yaw": atan2(to_fire.x, to_fire.z),
		"sitting": true,
	})
	return spots


## Житель на краю Площади по направлению на цель (зона), лицом к центру.
static func _edge_spot(
	art: IslandArt, character: int, toward: Vector2
) -> Dictionary:
	var plaza: Dictionary = IslandGen.ZONES[0]
	var center: Vector2 = plaza["center"]
	var dir := (toward - center).normalized()
	var pos2d := center + dir * PLAZA_EDGE
	return {
		"character": character,
		"pos": Vector3(pos2d.x, ground_height(art, pos2d.x, pos2d.y), pos2d.y),
		"yaw": atan2(-dir.x, -dir.y),
		"sitting": false,
	}


## Высота рельефа в точке (целочисленная клетка карты 257×257).
static func ground_height(art: IslandArt, x: float, z: float) -> float:
	if art == null or art.heights.is_empty():
		return 0.0
	var cx := clampi(int(round(x)), -IslandGen.HALF, IslandGen.HALF - 1)
	var cz := clampi(int(round(z)), -IslandGen.HALF, IslandGen.HALF - 1)
	return art.heights[(cz + IslandGen.HALF) * IslandGen.POINTS + cx + IslandGen.HALF]
