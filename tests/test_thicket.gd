# Расширение карты, сборка 3 — биом Чащи (юго-западное крыло за Лесом):
# второй лес — темнее и гуще существующего. Деревья (породы шумом
# _forest_kind, тон «leaf» — тёмно-зелёный зоны 7) через перешеек с
# разрежением, подлесок/валежник/сухостой — виды GroundDetails с гейтингом
# крыла, тропы-проходы держат просветы (деревья на них не встают, земля
# красится утоптанной), поляна-«комната» с дубом-исполином по образцу
# поляны гиганта Леса. Раскладки детерминированы; высоты не тронуты.
extends GutTest

const ART: IslandArt = preload("res://gameplay/world/island_art.res")
const WING_CENTER := Vector2(-130.0, -130.0)
const FOREST_CENTER := Vector2(-52.0, -52.0)
const FOREST_R: float = 40.0

## Виды Чащи (поле "zone": "thicket" в KINDS).
const THICKET_TYPES: PackedStringArray = [
	"gd_shrub2", "gd_shrub3", "gd_shrub4", "gd_rooibos",
	"gd_dlog1", "gd_dlog2", "gd_snag", "gd_dbranch1", "gd_dbranch2",
	"gd_roots2", "gd_moss1",
]

## Кэш наполнения между тестами файла (build дорогой: вся карта).
static var _gd_cache: Dictionary = {}
## Кэш данных генератора (generate ~1.5 мин, детерминирован; build
## детерминизма уже проверяет свежим вторым построением ниже).
static var _gen_cache: Dictionary = {}


func _gen() -> Dictionary:
	if _gen_cache.is_empty():
		_gen_cache = IslandGen.generate()
	return _gen_cache


func _scatter() -> Dictionary:
	if _gd_cache.is_empty():
		_gd_cache = GroundDetails.build(
			ART, GraphicsQuality.Tier.HIGH)["transforms"]
	return _gd_cache


func test_in_thicket_covers_wing_and_isthmus() -> void:
	# Биом — ядро крыла и перешеек от Леса; старый остров, чужие крылья
	# и чужие перешейки — нет.
	assert_true(IslandGen.in_thicket(-130, -130), "ядро Чащи")
	assert_true(IslandGen.in_thicket(-95, -95), "перешеек Лес→Чаща")
	assert_false(IslandGen.in_thicket(-52, -52), "старый Лес — не Чаща")
	assert_false(IslandGen.in_thicket(0, 10), "Площадь — не Чаща")
	assert_false(IslandGen.in_thicket(-170, 30), "Утёсы — не Чаща")
	assert_false(IslandGen.in_thicket(-11, -128), "перешеек Лугов — не Чаща")


func test_thicket_kinds_live_only_on_wing() -> void:
	# Все одиннадцать видов Чащи селятся заметно (не пара кустов) и только
	# в радиусе биома на новых землях (джиттер ±0.3 у кромки — с запасом);
	# старый остров и чужие крылья чисты.
	var transforms: Dictionary = _scatter()
	for type: String in THICKET_TYPES:
		var placed: Array = transforms.get(type, [])
		assert_gt(placed.size(), 10, "%s в Чаще заметен" % type)
		for xf: Transform3D in placed:
			assert_lt(
				Vector2(xf.origin.x, xf.origin.z).distance_to(WING_CENTER),
				IslandGen.THICKET_REACH_R + 1.0, "%s не выходит за биом" % type)
			# Клетка посадки: floori, не int — у отрицательных координат
			# int усекает к нулю, и джиттер ±0.3 кромки меняет клетку.
			assert_true(IslandGen._in_new_land(
				floori(xf.origin.x), floori(xf.origin.z)),
				"%s только на новых землях" % type)


func test_thicket_scatter_is_deterministic() -> void:
	# Два построения дают те же трансформы (свой rng, печёные высоты).
	var first: Dictionary = _scatter()
	var second: Dictionary = GroundDetails.build(
		ART, GraphicsQuality.Tier.HIGH)["transforms"]
	for type: String in THICKET_TYPES:
		assert_eq(first.get(type, []).size(), second.get(type, []).size(),
			"%s: столько же экземпляров" % type)
		for i: int in (first.get(type, []) as Array).size():
			assert_eq(first[type][i], second[type][i],
				"%s: трансформ %d совпадает" % [type, i])


func test_fern_returns_to_thicket() -> void:
	# Папоротник — прежний вид с крыла Чащи (гуще у стволов, как в Лесу).
	var transforms: Dictionary = _scatter()
	var fern := 0
	for xf: Transform3D in transforms.get("gd_fern", []):
		if Vector2(xf.origin.x, xf.origin.z).distance_to(WING_CENTER) \
				< IslandGen.THICKET_REACH_R:
			fern += 1
	assert_gt(fern, 5, "папоротник живёт в Чаще")


func test_thicket_forest_denser_than_old_forest() -> void:
	# Смысл крыла: второй лес ГУЩЕ существующего. Считаем деревья
	# (не кусты) на м² в старом Лесу и в Чаще по одним данным generate().
	var data: Dictionary = _gen()
	var forest_trees := 0
	var thicket_trees := 0
	var thicket_cells := 0
	for z: int in range(-IslandGen.HALF, IslandGen.HALF + 1):
		for x: int in range(-IslandGen.HALF, IslandGen.HALF + 1):
			if IslandGen.in_thicket(x, z):
				var h: float = ART.heights[IslandGen._idx(x, z)]
				if h > 0.9 and h <= 8.0:
					thicket_cells += 1
	for prop: Dictionary in data["props"]:
		var type := String(prop["type"])
		if not type.begins_with("etree_") or type == "etree_bush":
			continue
		var pos: Vector3 = prop["pos"]
		if Vector2(pos.x, pos.z).distance_to(FOREST_CENTER) < FOREST_R:
			forest_trees += 1
		elif IslandGen.in_thicket(int(pos.x), int(pos.z)):
			thicket_trees += 1
	assert_gt(thicket_trees, 300, "деревьев в Чаще заметно (> 300)")
	var forest_density: float = float(forest_trees) / (PI * FOREST_R * FOREST_R)
	var thicket_density: float = float(thicket_trees) / maxf(1.0, float(thicket_cells))
	assert_gt(thicket_density, forest_density * 1.2,
		"чаща гуще Леса (%.4f > %.4f × 1.2)" % [thicket_density, forest_density])


func test_thicket_trails_clear_and_walkable() -> void:
	# Тропы-проходы: деревья не встают на полосу тропы (просвет ≥ 2 м от
	# оси), земля красится утоптанной (вес ≥ 0.9 на оси, DIRT под ногами),
	# и каждая точка оси достижима пешком с Площади (BFS заливка с
	# барьерами коллизий) — чаща проходима насквозь.
	var data: Dictionary = _gen()
	# Клетки деревьев чащи (джиттер ±0.3, запрет при весе тропы ≥ 0.15 —
	# реальные просветы ~2.5 м от оси; порог теста 2.0 с запасом).
	var tree_cells: Array[Vector2] = []
	for prop: Dictionary in data["props"]:
		var type := String(prop["type"])
		if not type.begins_with("etree_") or type == "etree_bush":
			continue
		var pos: Vector3 = prop["pos"]
		if Vector2(pos.x, pos.z).distance_to(WING_CENTER) \
				< IslandGen.THICKET_REACH_R + 20.0:
			tree_cells.append(Vector2(pos.x, pos.z))
	var reach: Dictionary = IslandGen.mechanics_reach(data)["cells"]
	for line: PackedVector2Array in [
			IslandGen.THICKET_PATH_MAIN, IslandGen.THICKET_PATH_SOUTH]:
		for i: int in line.size() - 1:
			var a: Vector2 = line[i]
			var b: Vector2 = line[i + 1]
			var steps: int = int(a.distance_to(b)) + 1
			for s: int in steps + 1:
				var p := a.lerp(b, float(s) / float(maxi(1, steps)))
				for tree: Vector2 in tree_cells:
					assert_gt(tree.distance_to(p), 2.0,
						"дерево (%.1f, %.1f) не стоит на тропе" % [tree.x, tree.y])
				assert_gte(ForestGround._path_weight(p.x, p.y), 0.9,
					"ось тропы красится утоптанной землёй")
				# Покрытие под ногами — земля; на крутых клетках тропы
				# (уступы перешейка) приоритет камня законен, как у тропы
				# Леса, — там не проверяем. Клетка — roundi, как в
				# surface_kind (int у отрицательных усекает к нулю).
				var slope: float = ForestGround._slope(
					ART, roundi(p.x) + IslandGen.HALF, roundi(p.y) + IslandGen.HALF)
				if slope < ForestGround.ROCK_SLOPE_SOFT:
					assert_eq(ForestGround.surface_kind(
						ART, Vector3(p.x, 0.0, p.y)),
						ForestGround.Surface.DIRT, "под ногами на тропе — земля")
				assert_true(reach.has(Vector2i(int(p.x), int(p.y))),
					"точка тропы (%.0f, %.0f) достижима пешком" % [p.x, p.y])


func test_thicket_giant_clearing() -> void:
	# Поляна-«комната»: дуб-исполин на своей клетке, в радиусе чистки
	# никаких других деревьев (гуща вокруг, комната внутри).
	var data: Dictionary = _gen()
	var giant: Vector3 = Vector3.INF
	for prop: Dictionary in data["props"]:
		if String(prop["type"]) != "etree_giant":
			continue
		var pos: Vector3 = prop["pos"]
		if Vector2(pos.x, pos.z).distance_to(WING_CENTER) \
				< IslandGen.THICKET_REACH_R:
			assert_eq(giant, Vector3.INF, "гигант Чащи один")
			giant = pos
	assert_ne(giant, Vector3.INF, "гигант Чащи есть")
	assert_lt(Vector2(giant.x, giant.z).distance_to(
		Vector2(float(IslandGen.THICKET_GIANT_CELL.x),
			float(IslandGen.THICKET_GIANT_CELL.y))), 2.0,
		"гигант на клетке поляны")
	for prop: Dictionary in data["props"]:
		var type := String(prop["type"])
		if not type.begins_with("etree_") or type == "etree_bush" \
				or type == "etree_giant":
			continue
		var pos: Vector3 = prop["pos"]
		if IslandGen.in_thicket(int(pos.x), int(pos.z)):
			assert_gt(
				Vector2(pos.x, pos.z).distance_to(Vector2(giant.x, giant.z)),
				float(IslandGen.THICKET_GIANT_CLEAR_R),
				"поляна чиста от деревьев (r %d)" % IslandGen.THICKET_GIANT_CLEAR_R)


func test_thicket_moss_grows_thicker() -> void:
	# Атмосфера: пятна мха на крыле Чащи гуще (буст веса крыла), вне
	# крыла буста нет — формула совпадает с прежней точка в точку.
	var noise := FastNoiseLite.new()
	noise.seed = ForestGround.MOSS_SEED
	noise.frequency = ForestGround.MOSS_FREQUENCY
	# Пиксель центра Чащи: мир (−130, −130) → пиксель (−130 + 256).
	var patch: float = smoothstep(
		0.05, 0.75, (noise.get_noise_2d(126, 126) + 1.0) * 0.5)
	var expected: float = patch * (1.0 + ForestGround.THICKET_MOSS_BOOST) \
		* (0.45 + 0.55 * 0.5)
	assert_almost_eq(
		ForestGround._moss_weight(noise, 126, 126, 0.0, 0.5),
		expected, 0.001, "мох в ядре Чащи — с бустом крыла")
	# Площадь (мир (0, 4) → пиксель (256, 260)): буста нет.
	var patch_plaza: float = smoothstep(
		0.05, 0.75, (noise.get_noise_2d(256, 260) + 1.0) * 0.5)
	assert_almost_eq(
		ForestGround._moss_weight(noise, 256, 260, 0.0, 0.5),
		patch_plaza * (0.45 + 0.55 * 0.5), 0.001,
		"мох на Площади — без буста, прежняя формула")


func test_thicket_spawns_and_zone_intact() -> void:
	# Каркас сборки 1 не сломан: зона, спавн и камень духа Чащи на местах,
	# рядом с гущей есть проход (спавн достижим — через заливку).
	var data: Dictionary = _gen()
	assert_true(data["spawn_zones"].has("thicket"), "спавн THICKET есть")
	var reach: Dictionary = IslandGen.mechanics_reach(data)["cells"]
	var spawn: Vector3 = data["spawn_zones"]["thicket"]
	assert_true(reach.has(Vector2i(int(spawn.x), int(spawn.z))),
		"спавн Чащи достижим пешком с Площади")
	var wing_stones := 0
	for stone: Vector3 in data["stones"]:
		if Vector2(stone.x, stone.z).distance_to(WING_CENTER) < 60.0:
			wing_stones += 1
	assert_eq(wing_stones, 1, "камень духа Чащи один, на крыле")
