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
	# П5.13, блок 2: +2 швартовочных кнехта на конце причала Озера
	# (высоты и прочие предметы не менялись).
	# П5.13, блок 3: хеш обновлён сознательно — в generate() добавлена
	# гидравлическая эрозия склонов Холмов/Расщелины (детерминирована
	# собственным RNG от SEED_VALUE + 991, маска вырезает Лес, террасы
	# Площади/Руин и котловину Озера), высоты под ней изменились →
	# перегенерированы island.tscn/island_art.res/island_map.png, якоря
	# механик легли на новую карту высот. Механики, тропы, POI — прежние.
	# П5.13, блок 4: хеш обновлён сознательно — профиль весов zone_blend
	# стал smoothstep и появился спад силы зонального тона к краю охвата
	# (плавные границы зон, планка Ж); высоты и раскладка предметов не
	# менялись, сдвинулся только tint-тон предметов (входит в хеш).
	# Перегенерированы island.tscn/island_art.res/island_map.png.
	# П5.13, блок 5: хеш обновлён сознательно — деревня у Площади (3 домика
	# house + 12 секций забора fence, rng_static) и наполнение зон по
	# собственному RNG (FILLER_SEED): коряги/кусты/валуны лугов и Холмов,
	# деревья и коряги берега Озера, коряги двора Руин. Кусты etree_bush
	# наполнения посажены на интерполированный рельеф в фактической точке
	# (как деревья Леса, _prop с heights) — pos.y кустов изменился, поэтому
	# хеш обновлён вторично в рамках блока. Прежняя раскладка не сдвинулась
	# (свой поток чисел), высоты/тропы/POI прежние; проходимость с
	# наполнением — tests/test_walkability.gd.
	# Доработка П5.13, пункт 1: хеш обновлён сознательно — кольцо валунов
	# «boulder» у костра убрано из раскладки (кострище теперь CC0-модель
	# stone_fire_pit в узле Campfire, с шатром поленьев и коллизией очага);
	# остальная раскладка, высоты, тропы и POI не менялись.
	# Доработка П5.13, постройки: хеш обновлён сознательно — домики-срубы
	# «house» (серые коробки) убраны из деревни у Площади (в локальной
	# библиотеке моделей замены нет; дома жителей встанут готовой моделью,
	# сруб Kless в очереди владельца). Заборы-палисадники, якоря участков,
	# высоты, тропы и POI не менялись.
	# Доработка П5.13, дочистка: хеш обновлён сознательно — мобы удалены
	# из данных генератора (data["mobs"] больше нет: птицы, зверьки, золотой
	# светлячок; раздел 8 выведен из мира). Высоты, тропы, POI, предметы
	# и деревенские заборы не менялись.
	# Доработка-2 П5.13, П1: хеш обновлён сознательно — в конвейер высот
	# добавлен финальный лапласиан-сглаживание (_smooth_pass: рябь эрозии
	# уходит, склоны холмов линейны и не меняются, кромки террас/оврага/
	# смотровых защищены гашением веса у перепадов, близких к MAX_STEP),
	# поэтому высоты и посадки предметов сдвинулись на сантиметры.
	# Доработка-2 П5.13, П2: хеш обновлён снова — обходные тропы смотровых
	# убраны (уступы пешеходом не проходимы, только лестница/подсадка),
	# кольцо стен стало замкнутым (четыре стороны вместо трёх — сдвиг
	# потока rng раскладки). Раскладка зон и POI прежние; сглаживание
	# проверяет tests/test_terrain_lod.gd, проходимость — test_slope_walking.
	# Доработка-2 П5.13, П4: хеш обновлён — в двор руин добавлены пучки
	# травы и щебень у кромок стен («трава в щелях»); высоты, зоны, POI
	# и стены не менялись.
	assert_eq(first_hash, 3032273463, "хеш острова совпадает с сгенерированной сценой")


func test_zone_blend_is_smooth() -> void:
	# П5.13, блок 4 (планка Ж: бесшовность): итоговый зональный вклад
	# (цвет зоны × сила зоны — ровно то, что подмешивается к земле, туману
	# и тинтам предметов) меняется вдоль лучей между центрами зон без
	# шва — резкой смены на соседних метрах. До фикса силы зоны
	# нормализация mix/total держала полный тон до края охвата, и на метре
	# «зона кончилась» вклад выпадал скачком ~1.0 (замер пробы: 1.19 на
	# лучах ruins/lake — выбеленные линзы между зонами). Естественный
	# градиент растворения зоны — до 0.11 на метр (пик производной
	# smoothstep-профиля у самой узкой зоны, сумма трёх каналов); шов был
	# бы ≥ 0.5 (полная разница цветов зон). Порог 0.2 — отсекает шов,
	# градиент допускает.
	var pal: Palette = load("res://assets/palette.tres")
	var zones: Array = IslandGen.ZONES
	var from: Vector2 = zones[0]["center"]
	for zone: Dictionary in zones:
		var center: Vector2 = zone["center"]
		if center == from:
			continue
		var prev := _zone_contribution(from, pal.zone_ground)
		var steps := maxf(1, int(from.distance_to(center)))
		for s: int in range(1, steps + 1):
			var pos := from.lerp(center, float(s) / float(steps))
			var color := _zone_contribution(pos, pal.zone_ground)
			var jump: float = absf(color.r - prev.r) \
				+ absf(color.g - prev.g) + absf(color.b - prev.b)
			assert_lt(jump, 0.2,
				"зона %s: шов вклада на метре (шаг %d)" % [zone["name"], s])
			prev = color


## Зональный вклад в точке: цвет зоны, умноженный на силу зоны — как его
## используют point_color, туман и тинты (сила гасит вклад вне охвата).
func _zone_contribution(pos: Vector2, colors: PackedColorArray) -> Color:
	return IslandGen.zone_blend(pos, colors) \
		* IslandGen.zone_color_strength(pos)


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


func test_lookouts_not_reachable_even_with_decks() -> void:
	# Доработка-2 П5.13, П2: обходные тропы смотровых удалены — путь
	# «настилами» (walkable_reach учитывает предметы-поверхности) больше
	# не ведёт на площадки: только механики (лестница после подсадки).
	var data: Dictionary = _island_data()
	var reach: Dictionary = IslandGen.walkable_reach(data)
	for lookout: Vector2i in IslandGen.LOOKOUTS:
		assert_false(reach.has(lookout),
			"смотровая %s не достижима пешеходом и по настилам" % lookout)


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
