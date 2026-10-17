# Тесты генератора острова (раздел 6, этап П2; П4.5 — рельеф вместо GridMap):
# детерминизм — критерий этапа («тест на хеш данных острова»), достижимость
# всех зон пешком с площади
# и недостижимость смотровых без подсадки (9.3), точки появления на суше,
# HangPoint на кромке расщелины, параметры мобов из таблицы раздела 8.
# IslandGen — чистые данные, нод не нужно.
extends GutTest

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
	# П5.13, блок 1: хеш обновлён сознательно — kenney-модели заменены
	# процедурными (камни RockGen, трава/цветы/камыши ForestPlants, лавки,
	# колонны, арки), у Площади и Руин появились деревья и навесы, луга
	# переведены на лесную траву rgrass. Высоты, тропы, POI и кооп-механики
	# прежние (костёр, лавки, ворота, мосты), детерминизм — тестом выше.
	assert_eq(first_hash, 91068854, "хеш острова совпадает с сгенерированной сценой")


func test_heightmap_fully_covered() -> void:
	# Карта высот — сплошная сетка 257 × 257 на 256 × 256 м (П4.5:
	# из неё строится и меш, и HeightMapShape3D).
	var data: Dictionary = _island_data()
	var heights: PackedFloat32Array = data["heights"]
	assert_eq(heights.size(), IslandGen.POINTS * IslandGen.POINTS, "точек в карте")
	for height: float in heights:
		assert_false(is_nan(height), "карта без дыр (NaN)")


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


func test_forest_landmarks_giant_tree_and_gully_bridge() -> void:
	# П5.7, блок 2: ориентиры Леса — поляна с огромным деревом и овраг
	# с мостиком из брёвен на тропе. Гигант — ровно один, в центре своей
	# поляны; мостик — один, над дном русла; русло реально прорезано
	# (кромка выше дна больше чем на метр — внутрь не спрыгнуть по BFS
	# вверх), папоротники растут по дну и влажным низинам леса.
	var data: Dictionary = _island_data()
	var heights: PackedFloat32Array = data["heights"]
	var giants := 0
	var bridges := 0
	var ferns := 0
	for prop: Dictionary in data["props"]:
		match String(prop["type"]):
			"etree_giant":
				giants += 1
				var pos: Vector3 = prop["pos"]
				assert_almost_eq(
					pos.x, IslandGen.GIANT_CELL.x + 0.5, 0.1, "гигант в центре поляны")
				assert_almost_eq(
					pos.z, IslandGen.GIANT_CELL.y + 0.5, 0.1, "гигант в центре поляны")
			"log_bridge":
				bridges += 1
				var bridge_pos: Vector3 = prop["pos"]
				assert_almost_eq(
					bridge_pos.x, IslandGen.GULLY_MID.x, 0.1, "мостик на тропе, в середине русла")
				assert_almost_eq(
					bridge_pos.z, IslandGen.GULLY_MID.y, 0.1, "мостик на тропе, в середине русла")
			"fern":
				ferns += 1
	assert_eq(giants, 1, "огромное дерево на поляне — одно")
	assert_eq(bridges, 1, "мостик из брёвен через овраг — один")
	assert_gt(ferns, 30, "папоротники по дну оврага и низинам леса")
	# Русло прорезано: дно в середине ниже кромки на метр и больше.
	var mid := Vector2i(roundi(IslandGen.GULLY_MID.x), roundi(IslandGen.GULLY_MID.y))
	var bottom: float = heights[IslandGen._idx(mid.x, mid.y)]
	var across := Vector2(-IslandGen.GULLY_DIR.y, IslandGen.GULLY_DIR.x)
	var bank_flat: Vector2 = IslandGen.GULLY_MID + across * 3.2
	var bank: float = heights[IslandGen._idx(
		roundi(bank_flat.x), roundi(bank_flat.y))]
	assert_gt(bank - bottom, 0.9, "овраг глубже метра")


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
				assert_between(
					(mob["waypoints"] as Array).size(), 3, 5, "вейпоинтов в маршруте")
				assert_gte(
					(mob["points"] as Array).size(),
					(mob["waypoints"] as Array).size(),
					"маршрут плотнее вейпоинтов (по земле)")
				for point: Vector3 in mob["points"]:
					assert_gt(point.y, IslandGen.SEA_LEVEL, "маршрут по земле")
			"firefly":
				fireflies += 1
				assert_gt((mob["center"] as Vector3).y, IslandGen.SEA_LEVEL, "над сушей")
	assert_between(birds, 4, 12, "птиц на острове")
	assert_between(critters, 4, 8, "зверьков на острове")
	assert_between(fireflies, 2, 4, "светлячков на острове")


# --- Зверьки по земле и мимо предметов (vfx-fix, баг 3) ---


## Круги твёрдых предметов (x, z, radius) — как в отборе генератора.
func _solid_circles(data: Dictionary) -> Array[Vector3]:
	var circles: Array[Vector3] = []
	for prop: Dictionary in data["props"]:
		var size: Vector3 = PropMeshes.collision_size(
			StringName(prop["type"]), prop["scale"])
		if size == Vector3.ZERO:
			continue
		var pos: Vector3 = prop["pos"]
		circles.append(Vector3(pos.x, pos.z, maxf(size.x, size.z) * 0.5))
	return circles


## Каждая точка маршрута зверька — на высоте рельефа (та же триангуляция,
## что у меша) и вне запаса твёрдых предметов; в движении (сэмплы во
## времени) зверёк тоже не отрывается от земли.
func test_critter_routes_on_terrain_and_clear_of_props() -> void:
	var data: Dictionary = _island_data()
	var heights: PackedFloat32Array = data["heights"]
	var circles := _solid_circles(data)
	for mob: Dictionary in data["mobs"]:
		if String(mob["kind"]) != "critter":
			continue
		var points: Array = mob["points"]
		assert_gt(points.size(), 8, "маршрут плотный (не 3–5 редких точек)")
		var near: Array[Vector3] = []
		for circle: Vector3 in circles:
			for point: Vector3 in points:
				if Vector2(point.x, point.z).distance_to(Vector2(circle.x, circle.y)) \
						<= IslandGen.CRITTER_ROUTE_MAX:
					near.append(circle)
					break
		for point: Vector3 in points:
			assert_almost_eq(
				point.y, IslandGen.ground_height(heights, point.x, point.z), 0.02,
				"точка маршрута на высоте рельефа (%.1f, %.1f)" % [point.x, point.z])
			for circle: Vector3 in near:
				assert_gt(
					Vector2(point.x, point.z).distance_to(Vector2(circle.x, circle.y)),
					circle.z + IslandGen.CRITTER_CLEAR - 0.01,
					"точка маршрута вне предмета (%.1f, %.1f)" % [point.x, point.z])
		# Движение: сэмплы во времени не отрываются от земли (шаг 0.3 с —
		# мельче шага маршрута, проверка всей траектории, а не только узлов).
		for i: int in range(0, 300):
			var t: float = float(i) * 0.3
			var at := MobMotion.critter_position(mob, t)
			assert_almost_eq(
				at.y, IslandGen.ground_height(heights, at.x, at.z), 0.05,
				"зверёк на высоте рельефа (t=%.1f)" % t)
