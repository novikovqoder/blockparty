# Тесты генератора острова (раздел 6, этап П2; П4.5 — рельеф вместо GridMap):
# детерминизм — критерий этапа («тест на хеш данных острова»), ровно 60
# статичных монет (раздел 8), достижимость всех зон пешком с площади
# и недостижимость смотровых без подсадки (9.3), точки появления на суше,
# HangPoint на кромке расщелины, параметры мобов из таблицы раздела 8.
# IslandGen — чистые данные, нод не нужно.
extends GutTest

const B: Balance = preload("res://gameplay/balance.tres")

## Кэш данных генератора между тестами (generate() дорогой, ~10 с); тест
## детерминизма вызывает generate() отдельно — свежие данные каждый раз.
static var _gen_cache: Dictionary = {}


func _island_data() -> Dictionary:
	if _gen_cache.is_empty():
		_gen_cache = IslandGen.generate()
	return _gen_cache


func test_generation_is_deterministic() -> void:
	# Критерий этапа: повторная генерация даёт тот же остров.
	var first: Dictionary = IslandGen.generate()
	var second: Dictionary = IslandGen.generate()
	var first_hash: int = IslandGen.island_hash(first)
	var second_hash: int = IslandGen.island_hash(second)
	assert_eq(first_hash, second_hash, "хеш данных двух генераций совпадает")
	assert_eq(
		(first["props"] as Array).size(), (second["props"] as Array).size(),
		"число предметов совпадает",
	)
	# Хеш закреплён: непреднамеренное изменение генератора уронит этот тест
	# (намеренное — требует обновить константу и перегенерировать остров).
	assert_eq(first_hash, 112334720, "хеш острова совпадает с сгенерированной сценой")


func test_heightmap_fully_covered() -> void:
	# Карта высот — сплошная сетка 257 × 257 на 256 × 256 м (П4.5:
	# из неё строится и меш, и HeightMapShape3D).
	var data: Dictionary = _island_data()
	var heights: PackedFloat32Array = data["heights"]
	assert_eq(heights.size(), IslandGen.POINTS * IslandGen.POINTS, "точек в карте")
	for height: float in heights:
		assert_false(is_nan(height), "карта без дыр (NaN)")


func test_exactly_60_static_coins() -> void:
	# Раздел 8: на острове ровно 60 статичных монет (Balance.static_coins).
	var data: Dictionary = _island_data()
	assert_eq((data["coins"] as Array).size(), B.static_coins)


func test_all_zones_reachable_on_foot() -> void:
	# Критерий этапа: все зоны достижимы пешком с площади.
	var data: Dictionary = _island_data()
	var reach: Dictionary = IslandGen.walkable_reach(data)
	for zone: String in data["spawn_zones"]:
		var spawn: Vector3 = data["spawn_zones"][zone]
		var cell := Vector2i(int(floor(spawn.x)), int(floor(spawn.z)))
		assert_true(reach.has(cell), "зона %s достижима пешком" % zone)


func test_lookouts_not_reachable_without_help() -> void:
	# Раздел 9.3: по рельефу уступ в 3 м не взять — площадка недостижима без
	# подсадки (terrain_only исключает настилы); при этом базис-поляна вокруг
	# каждой смотровой достижим (к площадке вообще есть подход).
	var data: Dictionary = _island_data()
	var reach: Dictionary = IslandGen.walkable_reach(data, true)
	for lookout: Vector2i in IslandGen.LOOKOUTS:
		assert_false(reach.has(lookout), "смотровая %s не достижима по рельефу" % lookout)
		var base_reachable := false
		for dx: int in range(-7, 8):
			for dz: int in range(-7, 8):
				if absi(dx) <= 1 and absi(dz) <= 1:
					continue
				if reach.has(lookout + Vector2i(dx, dz)):
					base_reachable = true
		assert_true(base_reachable, "базис смотровой %s достижим" % lookout)


func test_lookouts_reachable_by_solo_trail() -> void:
	# Раздел 9.3, запасной путь: обходная тропа из досок ведёт на площадку —
	# одиночка поднимается без подсадки (настилы входят в поверхность).
	var data: Dictionary = _island_data()
	var reach: Dictionary = IslandGen.walkable_reach(data)
	for lookout: Vector2i in IslandGen.LOOKOUTS:
		assert_true(reach.has(lookout), "тропа ведёт на смотровую %s" % lookout)


func test_spawn_points_on_land() -> void:
	# Точки появления (--dev-spawn) стоят на суше выше уровня воды.
	var data: Dictionary = _island_data()
	for zone: String in data["spawn_zones"]:
		var spawn: Vector3 = data["spawn_zones"][zone]
		var top: float = IslandGen.top_of(data, int(floor(spawn.x)), int(floor(spawn.z)))
		assert_false(is_nan(top), "зона %s: клетка существует" % zone)
		assert_gt(top, IslandGen.SEA_LEVEL, "зона %s: точка выше воды" % zone)


func test_crevasse_hang_points_on_rim() -> void:
	# Раздел 9.1: HangPoint — на кромке расщелины, не на дне.
	var data: Dictionary = _island_data()
	var hang: Dictionary = data["hang"]
	var points: Array = hang["points"]
	assert_gt(points.size(), 0, "точки зацепа есть")
	var rim_y: float = IslandGen.CREVASSE_RIM_H
	var floor_y: float = IslandGen.CREVASSE_FLOOR_H
	for point: Vector3 in points:
		assert_almost_eq(point.y, rim_y + 0.1, 0.15, "точка на высоте кромки")
		assert_gt(point.y - floor_y, 3.0, "точка далеко над дном расщелины")
		var in_canyon: bool = point.x >= IslandGen.CREVASSE_X0 and point.x <= IslandGen.CREVASSE_X1 \
			and point.z >= IslandGen.CREVASSE_Z0 and point.z <= IslandGen.CREVASSE_Z1
		assert_false(in_canyon, "точка вне каньона — на стене у края")


func test_mobs_match_spec_table() -> void:
	# Раздел 8: птицы кружат (радиус 4–8, высота 2–4), зверьки — маршрут
	# из 3–5 точек, светлячки парят в лесу; spawn_id уникальны.
	var data: Dictionary = _island_data()
	var mobs: Array = data["mobs"]
	var birds := 0
	var critters := 0
	var fireflies := 0
	var ids: Dictionary = {}
	for mob: Dictionary in mobs:
		assert_false(ids.has(mob["spawn_id"]), "spawn_id уникален")
		ids[mob["spawn_id"]] = true
		match mob["kind"]:
			"bird":
				birds += 1
				assert_between(float(mob["radius"]), 4.0, 8.0, "радиус окружности")
				assert_between(float(mob["height"]), 2.0, 4.0, "высота полёта")
				assert_gt((mob["center"] as Vector3).y, IslandGen.SEA_LEVEL, "над сушей")
			"critter":
				critters += 1
				assert_between((mob["points"] as Array).size(), 3, 5, "точек в маршруте")
				for point: Vector3 in mob["points"]:
					assert_gt(point.y, IslandGen.SEA_LEVEL, "маршрут по земле")
			"firefly":
				fireflies += 1
				assert_gt((mob["center"] as Vector3).y, IslandGen.SEA_LEVEL, "над сушей")
	assert_between(birds, 4, 12, "птиц на острове")
	assert_between(critters, 4, 8, "зверьков на острове")
	assert_between(fireflies, 2, 4, "светлячков на острове")
