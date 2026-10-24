# Тесты проходимости с наполнением (П5.13, блок 5): деревня у Площади
# (заборы участков — срубы-домики убраны в доработке П5.13) и наполнение
# зон (деревья берега Озера, коряги, валуны, кусты) не отрезают механики
# и соло-пути. mechanics_reach — BFS по верхним поверхностям: рельеф,
# настилы и верхние грани коллизий твёрдых предметов (бокс расширен
# на радиус игрока). Предмет выше MAX_STEP (забор, ствол) — барьер;
# ниже (кольцо валунов костра, гребень стены каньона) —
# ступень, персонаж перешагивает автоподъёмом. Точка достижима, если занята
# клетка в радиусе подхода 1.6 м — у лавки игрок останавливается
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
	# ворота руин (декоративная рама — проём всегда открыт, механика
	# плит удалена с наследием born-unblessed), конец причала, HangPoint
	# расщелины,
	# участки деревни (палисадники без домиков — срубы убраны в доработке
	# П5.13, подход к будущим домам не зарос), места жителей и обе кромки
	# обоих мостков через каньон. Смотровых площадок в списке НЕТ —
	# доработка-2 П5.13 (П2) убрала обходные тропы: уступы пешеходом
	# не проходимы (см. test_lookouts_not_reachable_on_foot).
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
	# Плиты и сундук руин удалены с наследием (born-unblessed) — осталась
	# рама ворот (проём всегда открыт).
	points.append({"name": "ворота руин",
		"pos": data["poi"]["ruins"]["gate_center"]})
	points.append({"name": "конец причала", "pos": data["poi"]["pier"]["deck_end"]})
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
	var failed: Array[String] = []
	for point: Dictionary in points:
		if not _reachable(reach, point["pos"]):
			failed.append(String(point["name"]))
	assert_eq(failed.size(), 0,
		"все точки достижимы, застряли: %s" % ", ".join(failed))


func test_lookouts_not_reachable_on_foot() -> void:
	# Доработка-2 П5.13, П2: смотровые уступы пешеходом НЕ проходимы —
	# только механики (верёвочная лестница после подсадки, голова другого
	# игрока). Обходные тропы удалены из генератора; BFS по поверхностям
	# (шаг ≤ MAX_STEP, падение вниз разрешено) не должен находить путь
	# с земли на площадку ни одной из четырёх смотровых. Кольцо грунта
	# вокруг уступа (LOOKOUT_BASE_H) — наоборот, достижимо: к смотровой
	# можно подойти по склону холма.
	var data: Dictionary = _island_data()
	var walked: Dictionary = IslandGen.mechanics_reach(data)
	var reach: Dictionary = walked["cells"]
	var tops: Dictionary = walked["tops"]
	for lookout: Dictionary in data["poi"]["lookouts"]:
		var center: Vector3 = lookout["center"]
		var cell := Vector2i(int(floor(center.x)), int(floor(center.z)))
		assert_false(reach.has(cell) and not tops.has(cell),
			"площадка смотровой %s пешеходом недостижима" % center)
		# Кольцо-основание вокруг уступа достижимо: подход по склону есть
		# (клетки кольца — в 3–6 м от центра, за пределами самой скалы).
		var ring_reachable := false
		for dx: int in range(-6, 7):
			for dz: int in range(-6, 7):
				if maxi(absi(dx), absi(dz)) < 3:
					continue
				if reach.has(Vector2i(cell.x + dx, cell.y + dz)):
					ring_reachable = true
		assert_true(ring_reachable,
			"к смотровой %s есть подход по кольцу-основанию" % center)


func test_village_pads_flat_and_clear() -> void:
	# Деревня (сруб Kless): подушки участков плоские на PLAZA_H и проходимы
	# (BFS доходит до каждого центра участка — у каждой двери есть подход),
	# наполнение на подушки не заходит. Процедурных срубов-коробок и их
	# заборов в мире больше нет: дома — узлы-сцены Cabin1..3 (проход
	# внутрь — tests/test_cabin_house.gd).
	var data: Dictionary = _island_data()
	var walked: Dictionary = IslandGen.mechanics_reach(data)
	var reach: Dictionary = walked["cells"]
	var heights: PackedFloat32Array = data["heights"]
	var plots: Array = data["poi"]["village"]["plots"]
	for plot: Dictionary in plots:
		var base: Vector3 = plot["pos"]
		var cell := Vector2i(int(floor(base.x)), int(floor(base.z)))
		assert_true(reach.has(cell),
			"участок деревни %s достижим пешком" % base)
		for probe: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			var at := Vector2(base.x, base.z) + probe * 9.5
			assert_almost_eq(
				IslandGen.ground_height(heights, at.x, at.y),
				IslandGen.PLAZA_H, 0.05,
				"подушка %s плоская, проба %s" % [base, probe])
	assert_eq(int(data["props"].filter(func(p: Dictionary) -> bool:
			return String(p["type"]) == "fence").size()), 0,
		"заборные секции П5.13 убраны (двор сруба — терраса дома)")
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
