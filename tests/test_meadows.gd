# Расширение карты, сборка 5 — биом Лугов (северное крыло) и Мшистой
# низины (пятое крыло за Каньоном). Луга: открытое крыло — деревьев
# почти нет (редкие одиночные, крон не сгущают), печёные кочки травы
# гуще чащи, у редких валунов «гроздья» цветов; шесть цветочных
# дециматов Poly Haven селятся пятнами того же шума, что кочки и цветы
# демо (поле "patch"); поле цветов демо гуще — кап ×MEADOW_FLOWER_MULT
# по весу крыла; панорамный холм у северной кромки. Низина: сырая чаша
# 0.6–2.2 м, мох гуще чащи (HOLLOW_MOSS_BOOST), сухостой/папоротник/
# валежник — СВОИ ключи видов (меши те же, что у Чащи и Берега; один
# ключ = одно крыло, виды биомов не смешиваются — как gd_shoresnag
# Берега); перешеек от Каньона опущен до уровня чаши (h_mult 0.55) —
# путь в низину и обратно без ступеней > MAX_STEP. Раскладки
# детерминированы. Спавны meadows/hollow достижимы пешком с Площади.
extends GutTest

const ART: IslandArt = preload("res://gameplay/world/island_art.res")
const MEADOW_CENTER := Vector2(-10.0, -160.0)
const HOLLOW_CENTER := Vector2(60.0, 150.0)
const PLAZA_CENTER := Vector2(0.0, 10.0)

## Шесть цветочных видов Лугов (поле "zone": "meadows" в KINDS).
const MEADOW_TYPES: PackedStringArray = [
	"gd_empodium", "gd_gazania", "gd_ursinia",
	"gd_dandelion", "gd_periwinkle", "gd_celandine",
]

## Четыре вида Мшистой низины (поле "zone": "hollow"): мох, сухостой,
## папоротник (пятнами) и валежник — свои ключи крыла.
const HOLLOW_TYPES: PackedStringArray = [
	"gd_hollowmoss", "gd_hollowsnag", "gd_hollowfern", "gd_hollowlog",
]

## Чужие виды с теми же мешами (Чаща/Берег): в низине их быть не может.
const FOREIGN_SAME_MESH_TYPES: PackedStringArray = [
	"gd_moss1", "gd_snag", "gd_shoresnag", "gd_dlog1", "gd_dlog2",
]

## Кэш между тестами файла: build и generate дорогие (вся карта).
static var _gd_cache: Dictionary = {}
static var _data_cache: Dictionary = {}


func _scatter() -> Dictionary:
	if _gd_cache.is_empty():
		_gd_cache = GroundDetails.build(
			ART, GraphicsQuality.Tier.HIGH)["transforms"]
	return _gd_cache


func _island() -> Dictionary:
	if _data_cache.is_empty():
		_data_cache = IslandGen.generate()
	return _data_cache


func test_in_meadows_covers_wing_and_isthmus() -> void:
	# Биом — ядро крыла и перешеек от Леса; старый остров, чужие крылья
	# и чужие перешейки — нет.
	assert_true(IslandGen.in_meadows(-10, -160), "ядро Лугов")
	assert_true(IslandGen.in_meadows(-11, -128), "перешеек Лес→Луга")
	assert_true(IslandGen.in_meadows(-42, -188), "панорамный холм — Луга")
	assert_false(IslandGen.in_meadows(0, -40), "старый остров — не Луга")
	assert_false(IslandGen.in_meadows(0, 10), "Площадь — не Луга")
	assert_false(IslandGen.in_meadows(-130, -130), "Чаща — не Луга")
	assert_false(IslandGen.in_meadows(60, 100), "перешеек низины — не Луга")


func test_in_hollow_covers_wing_and_isthmus() -> void:
	# Биом — ядро крыла и перешеек от Каньона; чужие земли — нет.
	assert_true(IslandGen.in_hollow(60, 150), "ядро низины")
	assert_true(IslandGen.in_hollow(60, 116), "перешеек Каньон→низина")
	assert_true(IslandGen.in_hollow(58, 146), "спавн — низина")
	assert_false(IslandGen.in_hollow(56, 86), "старый остров — не низина")
	assert_false(IslandGen.in_hollow(0, 10), "Площадь — не низина")
	assert_false(IslandGen.in_hollow(-11, -128), "перешеек Лугов — не низина")


func test_meadows_kinds_live_only_on_wing() -> void:
	# Все шесть цветочных видов селятся заметно (не пара кустиков) и
	# только в радиусе биома на новых землях (джиттер ±0.3 у кромки —
	# с запасом); старый остров и чужие крылья чисты.
	var transforms: Dictionary = _scatter()
	for type: String in MEADOW_TYPES:
		var placed: Array = transforms.get(type, [])
		assert_gt(placed.size(), 10, "%s на Лугах заметен" % type)
		for xf: Transform3D in placed:
			assert_lt(
				Vector2(xf.origin.x, xf.origin.z).distance_to(MEADOW_CENTER),
				IslandGen.MEADOWS_REACH_R + 1.0,
				"%s не выходит за биом" % type)
			# Клетка посадки: floori, не int — у отрицательных координат
			# int усекает к нулю, и джиттер ±0.3 кромки меняет клетку.
			assert_true(IslandGen._in_new_land(
				floori(xf.origin.x), floori(xf.origin.z)),
				"%s только на новых землях" % type)


func test_hollow_kinds_live_only_on_wing() -> void:
	# Четыре вида низины — заметно и только в круге своего крыла; чужие
	# виды с теми же мешами (мох/сухостой Чащи и Берега) на низине
	# не селятся — один ключ = одно крыло.
	var transforms: Dictionary = _scatter()
	for type: String in HOLLOW_TYPES:
		var placed: Array = transforms.get(type, [])
		assert_gt(placed.size(), 10, "%s в низине заметен" % type)
		for xf: Transform3D in placed:
			assert_lt(
				Vector2(xf.origin.x, xf.origin.z).distance_to(HOLLOW_CENTER),
				IslandGen.HOLLOW_REACH_R + 1.0,
				"%s не выходит за биом" % type)
			assert_true(IslandGen._in_new_land(
				floori(xf.origin.x), floori(xf.origin.z)),
				"%s только на новых землях" % type)
	for type: String in FOREIGN_SAME_MESH_TYPES:
		for xf: Transform3D in transforms.get(type, []):
			assert_gt(
				Vector2(xf.origin.x, xf.origin.z).distance_to(HOLLOW_CENTER),
				IslandGen.HOLLOW_REACH_R + 1.0,
				"%s — чужой ключ, в низине его нет" % type)


func test_scatter_is_deterministic() -> void:
	# Два построения дают те же трансформы (свои rng, печёные высоты).
	var first: Dictionary = _scatter()
	var second: Dictionary = GroundDetails.build(
		ART, GraphicsQuality.Tier.HIGH)["transforms"]
	for type: String in MEADOW_TYPES + HOLLOW_TYPES:
		assert_eq(first.get(type, []).size(), second.get(type, []).size(),
			"%s: столько же экземпляров" % type)
		for i: int in (first.get(type, []) as Array).size():
			assert_eq(first[type][i], second[type][i],
				"%s: трансформ %d совпадает" % [type, i])


func test_flower_props_follow_patches() -> void:
	# Цветочные коврики селятся пятнами шума _grass_patch (поле "patch"):
	# средний вес пятна под посадками выше среднего по крылу — цветы
	# сгущаются там же, где кочки травы и цветы демо.
	var transforms: Dictionary = _scatter()
	var under_flowers := 0.0
	var flower_count := 0
	for type: String in MEADOW_TYPES:
		for xf: Transform3D in transforms.get(type, []):
			under_flowers += IslandGen._grass_patch(
				floori(xf.origin.x), floori(xf.origin.z))
			flower_count += 1
	assert_gt(flower_count, 60, "цветов хватает для статистики")
	assert_gt(under_flowers / float(flower_count), 0.5,
		"цветы сгущаются по пятнам (> 0.5)")


func test_meadow_flower_mats_below_waist() -> void:
	# Фикс «по колено» (приёмка этапа расширения: трава/цветы выше
	# героя): sanity высоты цветочных ковриков — AABB модели × верх
	# диапазона масштаба вида не выше пояса героя (рост 1.8 м, П10).
	const WAIST: float = 1.1
	for kind: Dictionary in GroundDetails.KINDS:
		if String(kind.get("zone", "")) != "meadows":
			continue
		var h: float = (kind["mesh"] as Mesh).get_aabb().size.y
		var scale: Vector2 = kind["scale"]
		assert_lte(h * scale.y, WAIST,
			"%s — коврик %.2f м не выше пояса" % [kind["type"], h * scale.y])


func test_meadows_trees_sparse_and_solitary() -> void:
	# Смысл крыла — открытость: деревьев мало и все одиночные (в коде
	# запрет соседей в 6 м; тест проверяет попарно 5 м с запасом джиттера).
	var data: Dictionary = _island()
	var trees: Array[Vector2] = []
	for prop: Dictionary in data["props"]:
		var type := String(prop["type"])
		if not type.begins_with("etree_") or type == "etree_bush":
			continue
		var pos: Vector3 = prop["pos"]
		if IslandGen.in_meadows(int(pos.x), int(pos.z)):
			trees.append(Vector2(pos.x, pos.z))
	assert_lt(trees.size(), 120, "деревьев на Лугах мало (< 120)")
	for i: int in trees.size():
		for j: int in range(i + 1, trees.size()):
			assert_gt(trees[i].distance_to(trees[j]), 5.0,
				"деревья %.0f и %.0f — одиночные, не группа" % [i, j])


func test_meadows_flower_field_denser_than_plaza() -> void:
	# Поле цветов демо гуще на Лугах: кап ×MEADOW_FLOWER_MULT по весу
	# крыла — цветы (flower_*) в чанках одного круга ULTRA вокруг
	# центров Лугов и Площади (площади кругов равны — сравнение чисел).
	var meadow := _flowers_around(MEADOW_CENTER)
	var plaza := _flowers_around(PLAZA_CENTER)
	assert_gt(meadow, 200, "цветов демо на Лугах заметно")
	assert_gt(meadow, plaza * 1.5,
		"поле Лугов гуще Площади (%d > %d × 1.5)" % [meadow, plaza])


func _flowers_around(center: Vector2) -> int:
	# Цветы демо (flower_*) в чанках круга ULTRA вокруг центра
	# (build_chunk возвращает группы верхним уровнем: tuft, flower_*).
	var count := 0
	for key: Vector2i in GrassField.chunk_keys(
			GraphicsQuality.Tier.ULTRA, center):
		var chunk: Dictionary = GrassField.build_chunk(
			ART, GraphicsQuality.Tier.ULTRA, key.x, key.y)
		for group: String in chunk:
			if group.begins_with("flower_"):
				count += (chunk[group]["transforms"] as Array).size()
	return count


func test_meadow_panorama_hill_walkable() -> void:
	# Панорамная точка: вершина холма заметно выше окрестностей крыла и
	# скат пологий — по четырём лучам от вершины до r = MEADOW_HILL_R + 8
	# перепад на метр ≤ MAX_STEP (пешком без подсадки, в обе стороны).
	var hill := Vector2i(
		int(IslandGen.MEADOW_HILL_C.x), int(IslandGen.MEADOW_HILL_C.y))
	var top: float = ART.heights[IslandGen._idx(hill.x, hill.y)]
	assert_gt(top, 6.0, "вершина панорамного холма выше 6 м")
	var wing_avg := 0.0
	for i: int in 8:
		var p := Vector2(30.0 * cos(TAU * i / 8.0), 30.0 * sin(TAU * i / 8.0))
		wing_avg += ART.heights[IslandGen._idx(
			hill.x + int(p.x), hill.y + int(p.y))]
	wing_avg /= 8.0
	assert_gt(top, wing_avg + 3.0, "вершина доминирует над крылом (+3 м)")
	var reach_r: int = int(IslandGen.MEADOW_HILL_R) + 8
	for dir: Vector2 in [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]:
		var prev: float = top
		for r: int in range(1, reach_r + 1):
			var h: float = ART.heights[IslandGen._idx(
				hill.x + int(dir.x * r), hill.y + int(dir.y * r))]
			assert_lte(absf(h - prev), IslandGen.MAX_STEP + 0.01,
				"скат холма пологий (луч %s, %d м)" % [dir, r])
			prev = h


func test_hollow_isthmus_two_way_walkable() -> void:
	# Перешеек к низине опущен до уровня чаши (h_mult 0.55, насыпь 2.2 м):
	# вдоль оси старый остров → перешеек → спавн низины перепад на метр
	# ≤ MAX_STEP В ОБЕ СТОРОНЫ — прежняя насыпь 4.0 м оставляла у чаши
	# одностороннюю ступень 1.8 м (вниз срыв, назад не подняться).
	var axis: Array[Vector2] = [
		Vector2(40, 80), Vector2(60, 116), Vector2(58, 146)]
	for i: int in axis.size() - 1:
		var a: Vector2 = axis[i]
		var b: Vector2 = axis[i + 1]
		var steps: int = int(a.distance_to(b))
		var prev: float = ART.heights[IslandGen._idx(int(a.x), int(a.y))]
		for s: int in range(1, steps + 1):
			var p := a.lerp(b, float(s) / float(steps))
			var h: float = ART.heights[IslandGen._idx(int(p.x), int(p.y))]
			assert_lte(absf(h - prev), IslandGen.MAX_STEP + 0.01,
				"ось перешейка пологая (участок %d, %d м)" % [i, s])
			prev = h


func test_hollow_moss_grows_thickest() -> void:
	# Атмосфера: пятна мха на низине гуще Чащи (буст HOLLOW_MOSS_BOOST
	# поверх THICKET_MOSS_BOOST), вне крыльев бустов нет — формула
	# прежняя точка в точку.
	var noise := FastNoiseLite.new()
	noise.seed = ForestGround.MOSS_SEED
	noise.frequency = ForestGround.MOSS_FREQUENCY
	# Пиксель центра низины: мир (60, 150) → пиксель (60 + 256, 150 + 256).
	var patch: float = smoothstep(
		0.05, 0.75, (noise.get_noise_2d(316, 406) + 1.0) * 0.5)
	var expected: float = patch * (1.0 + ForestGround.THICKET_MOSS_BOOST * 0.0
		+ ForestGround.HOLLOW_MOSS_BOOST) * (0.45 + 0.55 * 0.5)
	assert_almost_eq(
		ForestGround._moss_weight(noise, 316, 406, 0.0, 0.5),
		expected, 0.001, "мох в ядре низины — с двойным бустом")
	# Площадь (мир (0, 4) → пиксель (256, 260)): бустов нет.
	var patch_plaza: float = smoothstep(
		0.05, 0.75, (noise.get_noise_2d(256, 260) + 1.0) * 0.5)
	assert_almost_eq(
		ForestGround._moss_weight(noise, 256, 260, 0.0, 0.5),
		patch_plaza * (0.45 + 0.55 * 0.5), 0.001,
		"мох на Площади — без бустов, прежняя формула")


func test_hollow_bowl_low_and_wet() -> void:
	# Чаша низины сырая и низкая: высоты ядра крыла в 0.6–2.2 м —
	# ниже прочих крыльев (луга 1.5–5.5, чаща 2–6); выше 3 м в ядре
	# не бывает.
	var above := 0
	var cells := 0
	for z: int in range(110, 186):
		for x: int in range(20, 101):
			if not IslandGen.in_hollow(x, z):
				continue
			cells += 1
			if ART.heights[IslandGen._idx(x, z)] > 3.0:
				above += 1
	assert_gt(cells, 1000, "клеток чаши хватает для проверки")
	assert_eq(above, 0, "чаша ниже 3 м (сырая низина)")


func test_meadows_and_hollow_spawns_reachable() -> void:
	# Каркас не сломан: зоны в ZONES и палитре, спавны достижимы пешком
	# с Площади (заливка с барьерами коллизий предметов).
	var data: Dictionary = _island()
	var reach: Dictionary = IslandGen.mechanics_reach(data)["cells"]
	for zone: String in ["meadows", "hollow"]:
		assert_true(data["spawn_zones"].has(zone), "спавн %s есть" % zone)
		var spawn: Vector3 = data["spawn_zones"][zone]
		assert_true(reach.has(Vector2i(int(spawn.x), int(spawn.z))),
			"спавн %s достижим пешком с Площади" % zone)
	assert_ne(Palette.zone_index("meadows"), -1, "Луга в палитре")
	assert_ne(Palette.zone_index("hollow"), -1, "низина в палитре")
