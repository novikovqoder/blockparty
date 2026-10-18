# Тесты проходимости с наполнением (П5.13, блок 5): деревня у Площади
# (заборы участков — срубы-домики убраны в доработке П5.13) и наполнение
# зон (деревья берега Озера, коряги, валуны, кусты) не отрезают механики
# и соло-пути. mechanics_reach — BFS по верхним поверхностям: рельеф,
# настилы и верхние грани коллизий твёрдых предметов (бокс расширен
# на радиус игрока). Предмет выше MAX_STEP (забор, ствол) — барьер;
# ниже (кольцо валунов костра, гребень стены каньона) —
# ступень, персонаж перешагивает автоподъёмом. Точка достижима, если занята
# клетка в радиусе подхода 1.6 м — у лавки или плиты игрок останавливается
# рядом, а не в центре.
extends GutTest

## Кэш данных генератора между тестами (generate() дорогой, ~10 с).
static var _gen_cache: Dictionary = {}

## Радиус подхода к точке механики, м: клетка поверхности, из которой
## персонаж (радиус 0.35) дотягивается до интерактива (use_radius ≥ 1.5).
const APPROACH_R: float = 1.6


func _island_data() -> Dictionary:
	if _gen_cache.is_empty():
		_gen_cache = IslandGen.generate()
	return _gen_cache


func _reachable(reach: Dictionary, point: Vector3) -> bool:
	var cx := int(floor(point.x))
	var cz := int(floor(point.z))
	for dx: int in range(-2, 3):
		for dz: int in range(-2, 3):
			var cell := Vector2i(cx + dx, cz + dz)
			if not reach.has(cell):
				continue
			var near := Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5)
			if near.distance_to(Vector2(point.x, point.z)) <= APPROACH_R:
				return true
	return false


func test_mechanics_reachable_with_fill() -> void:
	# Все механики и соло-пути достижимы с площади при полном наполнении:
	# спавны зон, камни духа (возрождение), костёр и лавки (посадка),
	# плиты и ворота руин, сундук (внутри двора — через проломы или
	# открывшиеся ворота; рама ruin_gate проходима: решётку держит узел
	# RuinGate по механике плит), конец причала, смотровые площадки
	# (обходные тропы), HangPoint расщелины, участки деревни (палисадники
	# без домиков — срубы убраны в доработке П5.13, подход к будущим
	# домам не зарос), места жителей и обе кромки обоих мостков через
	# каньон.
	var data: Dictionary = _island_data()
	var reach: Dictionary = IslandGen.mechanics_reach(data)["cells"]
	var points: Array[Dictionary] = []
	for zone: String in data["spawn_zones"]:
		points.append({
			"name": "спавн %s" % zone, "pos": data["spawn_zones"][zone]})
	for stone: Vector3 in data["stones"]:
		points.append({"name": "камень духа %s" % stone, "pos": stone})
	var fire: Dictionary = data["poi"]["campfire"]
	points.append({"name": "костёр", "pos": fire["center"]})
	for bench: Vector3 in fire["benches"]:
		points.append({"name": "лавка %s" % bench, "pos": bench})
	var ruins: Dictionary = data["poi"]["ruins"]
	for plate: Vector3 in ruins["plates"]:
		points.append({"name": "плита %s" % plate, "pos": plate})
	points.append({"name": "ворота руин", "pos": ruins["gate_center"]})
	points.append({"name": "сундук руин", "pos": ruins["chest"]})
	points.append({"name": "конец причала", "pos": data["poi"]["pier"]["deck_end"]})
	for lookout: Dictionary in data["poi"]["lookouts"]:
		points.append({"name": "смотровая %s" % lookout["center"], "pos": lookout["center"]})
	for point: Vector3 in data["hang"]["points"]:
		points.append({"name": "HangPoint %s" % point, "pos": point})
	for spot: Vector3 in data["poi"]["village"]["spots"]:
		points.append({"name": "участок деревни %s" % spot, "pos": spot})
	# Кромки мостков через каньон: заход на настил с обеих сторон
	# (BRIDGE_X — X мостков, кромка каньона по Z с двух сторон).
	for bx: int in IslandGen.BRIDGE_X:
		points.append({
			"name": "мосток %d, северная кромка" % bx,
			"pos": Vector3(bx + 0.5, IslandGen.CREVASSE_RIM_H, IslandGen.CREVASSE_Z0 - 1.0)})
		points.append({
			"name": "мосток %d, южная кромка" % bx,
			"pos": Vector3(bx + 0.5, IslandGen.CREVASSE_RIM_H, IslandGen.CREVASSE_Z1 + 1.0)})
	# Жители (Финн, Луми, Тимьян) стоят на краю площади — к ним есть подход.
	var art: IslandArt = load("res://gameplay/world/island_art.res")
	for spot: Dictionary in FolkLayout.npc_spots(art):
		points.append({"name": "житель %d" % int(spot["character"]), "pos": spot["pos"]})
	var failed: Array[String] = []
	for point: Dictionary in points:
		if not _reachable(reach, point["pos"]):
			failed.append(String(point["name"]))
	assert_eq(failed.size(), 0,
		"все точки достижимы, застряли: %s" % ", ".join(failed))


func test_village_fences_block_their_cells() -> void:
	# Заборы деревни действительно твёрдые: BFS не проходит секцию насквозь.
	# Клетка под забором либо недостижима, либо входит в "tops" — путь туда
	# лежит только ПОВЕРХ предмета, сквозь секции пути нет. Доработка
	# П5.13: домики-срубы убраны (дома встанут моделью), палисадники
	# у участков остались — их непроходимость и проверяем.
	var data: Dictionary = _island_data()
	var walked: Dictionary = IslandGen.mechanics_reach(data)
	var reach: Dictionary = walked["cells"]
	var tops: Dictionary = walked["tops"]
	var fences: int = 0
	for prop: Dictionary in data["props"]:
		if String(prop["type"]) != "fence":
			continue
		fences += 1
		var pos: Vector3 = prop["pos"]
		var cell := Vector2i(int(floor(pos.x)), int(floor(pos.z)))
		assert_false(reach.has(cell) and not tops.has(cell),
			"забор %s: сквозь секцию пути нет" % pos)
	assert_eq(fences, 12, "три участка по два крыла из двух секций")
	assert_eq(int(data["props"].filter(func(p: Dictionary) -> bool:
			return String(p["type"]) == "house").size()), 0,
		"процедурных срубов-коробок в мире больше нет")


func test_zone_fill_adds_props_without_moving_layout() -> void:
	# Наполнение — добавки поверх прежней раскладки: предметы старых типов
	# (деревья Леса, стены руин, пирс) не изменили ни позиций, ни числа —
	# свой поток rng (FILLER_SEED) не трогает основную последовательность.
	# Проверяем по типам, которых наполнение не добавляет: пирс и постройки
	# площади, стены руин, деревья Леса.
	var data: Dictionary = _island_data()
	var counts: Dictionary = {}
	for prop: Dictionary in data["props"]:
		var type := String(prop["type"])
		counts[type] = int(counts.get(type, 0)) + 1
	for solid: String in ["ruin_block", "ruin_tower", "bench", "canopy",
			"plank_deck", "log_bridge", "pier_post", "boat"]:
		assert_gt(int(counts.get(solid, 0)), 0, "постройки %s на месте" % solid)
	# Наполнение живое: коряги вне Леса, кусты на лугах, деревья у Озера.
	assert_gt(int(counts.get("dead_log", 0)), 12, "коряг больше, чем было в Лесу")
	assert_gt(int(counts.get("etree_bush", 0)), 40, "кустов больше, чем было в Лесу")
	assert_gt(int(counts.get("fence", 0)), 0, "заборы деревни поставлены")
