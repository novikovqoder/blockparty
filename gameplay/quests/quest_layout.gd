# Детерминированная расстановка заданий жителей (П5.5): мята в Лесу
# (RandomNumberGenerator от SEED_VALUE — правило проекта, свой поток,
# как rng_static у пирса), вехи Финна константами относительно зон
# (маршрут Площадь → Расщелина → Руины через мостки), места жителей
# у площади и точки квестовых маяков. Высоты — из запечённой карты
# IslandArt (той же выборкой пользуется Starfall). Чистые функции:
# одинаковые позиции у хоста и клиентов без передачи по сети.
class_name QuestLayout
extends RefCounted

const B: Balance = preload("res://gameplay/balance.tres")

## Своя соль потока мяты: правки леса в генераторе не двигают мяту.
const MINT_SEED_SALT: int = 5077
## Пучков мяты (ТЗ: пять).
const MINT_COUNT: int = 5
## Запас попыток поиска места мяты (дальше — страховочное кольцо).
const MINT_ATTEMPTS: int = 600

## Вехи Финна (XZ; высота — из карты). Маршрут: выход с Площади, мосток
# x=33 через Расщелину, веха сразу за северной кромкой, спуск мостком x=52
# и финиш у ворот руин (арки 51,−45 / 65,−53). С мостка можно сорваться —
# работает существующее вытягивание.
const FLAG_POINTS: Array[Vector2] = [
	Vector2(16.0, 22.0),
	Vector2(33.0, 46.0),
	Vector2(33.0, 68.0),
	Vector2(58.0, -42.0),
]

## Жители: Финн (0) у выхода к Расщелине, Луми (1) у тропы к Холмам,
## Тимьян (2) сидит у костра между лавками (угол 0° — лавки на PI/8 + k·PI/4).
## Отступ от центра площади и от костра, м.
const PLAZA_EDGE: float = 15.0
const THYME_STUMP_DIST: float = 2.2
## Центр костра (IslandGen._campfire_and_board).
const CAMPFIRE: Vector3 = Vector3(0.5, 2.0, 2.5)


## Пять пучков мяты в Лесу: на земле выше кромки воды, не внутри предметов
## (боксы коллизий из запечённого арта), с взаимным разносом.
static func mint_positions(art: IslandArt) -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	rng.seed = IslandGen.SEED_VALUE + MINT_SEED_SALT
	var zone: Dictionary = IslandGen.ZONES[1]  # forest
	var center: Vector2 = zone["center"]
	var radius: float = float(zone["radius"]) - 6.0
	var found: Array[Vector3] = []
	for _i: int in MINT_ATTEMPTS:
		if found.size() >= MINT_COUNT:
			break
		var angle := rng.randf_range(0.0, TAU)
		var dist := sqrt(rng.randf_range(0.1, 1.0)) * radius
		var x := center.x + cos(angle) * dist
		var z := center.y + sin(angle) * dist
		var y := ground_height(art, x, z)
		if y < B.quest_mint_min_height:
			continue
		if not clear_of_props(art, Vector3(x, y, z), 0.9):
			continue
		var spaced := true
		for other: Vector3 in found:
			if Vector2(x, z).distance_to(Vector2(other.x, other.z)) < B.quest_mint_spacing:
				spaced = false
				break
		if not spaced:
			continue
		found.append(Vector3(x, y, z))
	# Страховка детерминизма: если фильтры оказались жёстче запаса попыток —
	# добираем кольцами вокруг центра леса (позиции всё же есть у всех).
	var ring := 10.0
	while found.size() < MINT_COUNT:
		for i: int in MINT_COUNT:
			if found.size() >= MINT_COUNT:
				break
			var angle := TAU * float(i) / float(MINT_COUNT) + ring * 0.7
			var pos := Vector3(
				center.x + cos(angle) * ring,
				0.0,
				center.y + sin(angle) * ring,
			)
			pos.y = ground_height(art, pos.x, pos.z)
			found.append(pos)
		ring += 6.0
	return found


## Вехи Финна на своей высоте рельефа.
static func flag_positions(art: IslandArt) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for point: Vector2 in FLAG_POINTS:
		positions.append(
			Vector3(point.x, ground_height(art, point.x, point.y), point.y)
		)
	return positions


## Места жителей: {character, quest_id, pos, yaw, sitting}. Все смотрят
## к центру площади; Тимьян — к костру.
static func npc_spots(art: IslandArt) -> Array[Dictionary]:
	var spots: Array[Dictionary] = []
	# Финн: у выхода с Площади в сторону Расщелины (62, 57).
	spots.append(_edge_spot(art, 0, Protocol.QUEST_FINN, Vector2(62.0, 57.0)))
	# Луми: у края Площади, у тропы к Холмам (-58, 42).
	spots.append(_edge_spot(art, 1, Protocol.QUEST_LUMI, Vector2(-58.0, 42.0)))
	# Тимьян: сидит у костра между лавками, лицом к огню.
	var stump := Vector3(CAMPFIRE.x + THYME_STUMP_DIST, 0.0, CAMPFIRE.z)
	stump.y = ground_height(art, stump.x, stump.z)
	var to_fire := (CAMPFIRE - stump).normalized()
	spots.append({
		"character": 2,
		"quest_id": Protocol.QUEST_THYME,
		"pos": stump,
		"yaw": atan2(to_fire.x, to_fire.z),
		"sitting": true,
	})
	return spots


## Житель на краю Площади по направлению на цель (зона), лицом к центру.
static func _edge_spot(
	art: IslandArt, character: int, quest_id: String, toward: Vector2
) -> Dictionary:
	var plaza: Dictionary = IslandGen.ZONES[0]
	var center: Vector2 = plaza["center"]
	var dir := (toward - center).normalized()
	var pos2d := center + dir * PLAZA_EDGE
	return {
		"character": character,
		"quest_id": quest_id,
		"pos": Vector3(pos2d.x, ground_height(art, pos2d.x, pos2d.y), pos2d.y),
		"yaw": atan2(-dir.x, -dir.y),
		"sitting": false,
	}


## Точки квестовых маяков Луми: {world_target, pos}. Первые два — у подножия
## существующих башен «Маяков» (Холмы −58,22 и Озеро −14,76; узел башни
## QuestSystem находит ближайшим к world_target и ставит огонёк рядом —
## переиспользуем объекты, новых башен не строим), третий — на смотровой
## площадке (та, что требует подсадки), pos готовый.
static func quest_beacon_spots(art: IslandArt) -> Array[Dictionary]:
	return [
		{
			"world_target": Vector2(-58.0, 22.0),
			"pos": Vector3(-58.0, ground_height(art, -58.0, 22.0), 22.0),
		},
		{
			"world_target": Vector2(-14.0, 76.0),
			"pos": Vector3(-14.0, ground_height(art, -14.0, 76.0), 76.0),
		},
		{
			"world_target": Vector2(NAN, NAN),
			"pos": Vector3(
				float(IslandGen.LOOKOUTS[2].x) + 0.8,
				IslandGen.LOOKOUT_TOP_H,
				float(IslandGen.LOOKOUTS[2].y) - 0.8,
			),
		},
	]


## Высота рельефа в точке (та же выборка, что у Starfall: целочисленная
## клетка карты 257×257).
static func ground_height(art: IslandArt, x: float, z: float) -> float:
	if art == null or art.heights.is_empty():
		return 0.0
	var cx := clampi(int(round(x)), -IslandGen.HALF, IslandGen.HALF - 1)
	var cz := clampi(int(round(z)), -IslandGen.HALF, IslandGen.HALF - 1)
	return art.heights[(cz + IslandGen.HALF) * IslandGen.POINTS + cx + IslandGen.HALF]


## Не внутри предмета: XZ-точка вне запаса вокруг бокса коллизии
## (грубая оценка максимальной полуширины покрывает и повёрнутые боксы).
static func clear_of_props(art: IslandArt, pos: Vector3, margin: float) -> bool:
	for collider: Dictionary in art.colliders:
		var cpos: Vector3 = collider["pos"]
		var size: Vector3 = collider["size"]
		if absf(pos.y - cpos.y) > 4.0:
			continue
		var flat := Vector2(pos.x - cpos.x, pos.z - cpos.z)
		if flat.length() <= margin + maxf(size.x, size.z) * 0.5:
			return false
	return true
