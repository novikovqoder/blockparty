# Расширение карты, сборка 4 — биом Берега (восточное крыло): песчаное
# побережье. Песок красит низкое крыло (ForestGround.sand_weight: вес
# крыла × спад по высоте с шумом) и только его; галька, ракушки и глыбы
# (поле "zone": "shore") живут на крыле до самой кромки воды — пляжный
# запрет BEACH_H для них снят, ниже SHORE_KIND_H_MIN воды никого нет;
# сухостой — общий вид с Чащей; кострище дикого пляжа — одна постановка
# у камня духа. Пляж проходим: спавн и низкие клетки ядра достижимы
# пешком с Площади; пара прибрежных глыб CliffLandmarks смотрит лицом
# на восток. Раскладки детерминированы — два построения дают те же
# трансформы.
extends GutTest

const ART: IslandArt = preload("res://gameplay/world/island_art.res")
const WING_CENTER := Vector2(170.0, -20.0)
const STONE_CELL := Vector2(166.5, -23.5)

## Виды Берега (поле "zone": "shore" в KINDS); сухостой gd_snag — общий
## с Чащей (поле "zones"), для него здесь только счёт на крыле.
const SHORE_TYPES: PackedStringArray = [
	"gd_sandrock", "gd_shell", "gd_coastrock",
]
const SCATTER_TYPES: PackedStringArray = [
	"gd_sandrock", "gd_shell", "gd_coastrock", "gd_snag", "gd_firepit",
]

## Кэш наполнения между тестами файла (build дорогой: вся карта).
static var _gd_cache: Dictionary = {}


func _scatter() -> Dictionary:
	if _gd_cache.is_empty():
		_gd_cache = GroundDetails.build(
			ART, GraphicsQuality.Tier.HIGH)["transforms"]
	return _gd_cache


func test_shore_sand_paints_wing_and_nowhere_else() -> void:
	# Песчаное покрытие заметное и целиком на крыле Берега; чужие земли
	# (Площадь, Лес, Утёсы, Чаща, Луга) — ровно ноль.
	var sandy := 0
	for z: int in range(-IslandGen.HALF, IslandGen.HALF + 1, 2):
		for x: int in range(-IslandGen.HALF, IslandGen.HALF + 1, 2):
			var h: float = ART.heights[IslandGen._idx(x, z)]
			if ForestGround.sand_weight(float(x), float(z), h) > 0.5:
				sandy += 1
				assert_lt(
					Vector2(float(x), float(z)).distance_to(WING_CENTER),
					65.0 + IslandGen.WING_EDGE_BAND + 1.0,
					"песок только на крыле Берега (%d, %d)" % [x, z])
	assert_gt(sandy, 300, "покрытие заметное (> 300 точек с шагом 2 м)")
	for far: Vector2 in [
			Vector2(0.0, 4.0), Vector2(-52.0, -52.0), Vector2(-170.0, 30.0),
			Vector2(-130.0, -130.0), Vector2(-10.0, -160.0)]:
		var h: float = IslandGen.ground_height(ART.heights, far.x, far.y)
		assert_almost_eq(ForestGround.sand_weight(far.x, far.y, h),
			0.0, 0.0001, "вне Берега песка нет (%.0f, %.0f)" % [far.x, far.y])


func test_shore_low_ground_fully_sandy() -> void:
	# Всё ниже плато крыла (~2.4 м: пологий склон к воде) — полный песок
	# (вес ≥ 0.88 даже при худшем джиттере шума ±SHORE_SAND_NOISE_AMP);
	# плато ~3.0 м накрыто FULL-порогом и проверяется пятнами прохода
	# test_shore_sand_paints. «Полный» — в ядре крыла (wing ≥ 0.9): в
	# полосе спада кромки вес крыла честно снижает песок — там переход
	# песок→море рваный, как задумано. Замер рельефа: ядро крыла —
	# плато ~3 м, клеток ниже 2.4 в нём ~80 — проверяем все.
	var checked := 0
	for z: int in range(-85, 46):
		for x: int in range(105, 236):
			if IslandGen.wing_weight_of("shore", x, z) < 0.9:
				continue
			var h: float = ART.heights[IslandGen._idx(x, z)]
			if h < 0.36 or h > 2.4:
				continue
			assert_gte(ForestGround.sand_weight(float(x), float(z), h), 0.88,
				"низкая клетка крыла — полный песок (%d, %d)" % [x, z])
			checked += 1
	assert_gt(checked, 50, "низких клеток ядра крыла хватило для проверки")


func test_shore_kinds_live_only_on_wing() -> void:
	# Виды Берега селятся заметно и только в круге своего крыла на новых
	# землях; сухостой дрейфует и на Берег (общий вид с Чащей).
	var transforms: Dictionary = _scatter()
	var wing_span: float = 65.0 + IslandGen.WING_EDGE_BAND + 2.0
	for type: String in SHORE_TYPES:
		var placed: Array = transforms.get(type, [])
		assert_gt(placed.size(), 6, "%s на Берегу заметен" % type)
		for xf: Transform3D in placed:
			assert_lt(
				Vector2(xf.origin.x, xf.origin.z).distance_to(WING_CENTER),
				wing_span, "%s не выходит за крыло Берега" % type)
			assert_true(IslandGen._in_new_land(
					floori(xf.origin.x), floori(xf.origin.z)),
				"%s только на новых землях" % type)
	var snags := 0
	for xf: Transform3D in transforms.get("gd_snag", []):
		if Vector2(xf.origin.x, xf.origin.z).distance_to(WING_CENTER) \
				< wing_span:
			snags += 1
	assert_gt(snags, 3, "сухостой дрейфует и на Берег")


func test_shore_kinds_live_on_sand() -> void:
	# Виды Берега живут на песке: большинство экземпляров гальки и
	# ракушек стоит на клетках с весом песка (запрет BEACH_H снят —
	# плато крыла и есть песчаный пляж), никто не стоит в воде.
	var transforms: Dictionary = _scatter()
	for type: String in ["gd_sandrock", "gd_shell"]:
		var placed: Array = transforms.get(type, [])
		var on_sand := 0
		for xf: Transform3D in placed:
			var sand: float = ForestGround.sand_weight(
				xf.origin.x, xf.origin.z, xf.origin.y + 0.3)
			if sand >= 0.4:
				on_sand += 1
		assert_gt(on_sand * 100, placed.size() * 70,
			"%s: ≥ 70%% на песке (%d из %d)" % [type, on_sand, placed.size()])
	for type: String in SHORE_TYPES:
		for xf: Transform3D in transforms.get(type, []):
			assert_gt(xf.origin.y, GroundDetails.SHORE_KIND_H_MIN - 0.1,
				"%s не в воде (y %.2f)" % [type, xf.origin.y])


func test_shore_scatter_is_deterministic() -> void:
	# Два построения дают те же трансформы (свой rng, печёные высоты).
	var first: Dictionary = _scatter()
	var second: Dictionary = GroundDetails.build(
		ART, GraphicsQuality.Tier.HIGH)["transforms"]
	for type: String in SCATTER_TYPES:
		assert_eq(first.get(type, []).size(), second.get(type, []).size(),
			"%s: столько же экземпляров" % type)
		for i: int in (first.get(type, []) as Array).size():
			assert_eq(first[type][i], second[type][i],
				"%s: трансформ %d совпадает" % [type, i])


func test_shore_firepit_single_near_spirit_stone() -> void:
	# Кострище дикого пляжа: одна постановка на своей клетке, на суше,
	# не на камне духа и не на спавне.
	var transforms: Dictionary = _scatter()
	var pits: Array = transforms.get("gd_firepit", [])
	assert_eq(pits.size(), 1, "кострище одно")
	var pit: Transform3D = pits[0]
	assert_lt(
		Vector2(pit.origin.x, pit.origin.z).distance_to(Vector2(
			float(GroundDetails.SHORE_FIREPIT_CELL.x) + 0.5,
			float(GroundDetails.SHORE_FIREPIT_CELL.y) + 0.5)),
		1.0, "кострище на своей клетке")
	assert_gt(pit.origin.y, 0.5, "кострище на суше, не в воде")
	assert_gt(
		Vector2(pit.origin.x, pit.origin.z).distance_to(STONE_CELL), 2.0,
		"кострище не на камне духа")
	assert_gt(
		Vector2(pit.origin.x, pit.origin.z).distance_to(Vector2(170.5, -15.5)),
		2.0, "кострище не на спавне")


func test_shore_beach_walkable_spawn_and_stone() -> void:
	# Каркас сборки 1 не сломан: спавн Берега и камень духа на местах
	# (один), пляж проходим — низкие клетки ядра достижимы пешком с
	# Площади (BFS заливка с барьерами коллизий).
	var data: Dictionary = IslandGen.generate()
	var reach: Dictionary = IslandGen.mechanics_reach(data)["cells"]
	assert_true(data["spawn_zones"].has("shore"), "спавн Берега есть")
	var spawn: Vector3 = data["spawn_zones"]["shore"]
	assert_lt(Vector2(spawn.x, spawn.z).distance_to(Vector2(170.5, -15.5)),
		1.5, "спавн на клетке (170, -16)")
	assert_true(reach.has(Vector2i(int(spawn.x), int(spawn.z))),
		"спавн Берега достижим пешком с Площади")
	# Пляж — песчаное плато крыла: сэмпл песчаных клеток суши (вес ≥ 0.5,
	# шаг 4, выше ватерлинии 0.4 — вес песка у кромки красит и дно, но
	# механики по воде не ходят) плюс вся низкая полоса у самой воды —
	# достижимы пешком.
	var checked := 0
	var edge := 0
	for z: int in range(-85, 46):
		for x: int in range(105, 236):
			if IslandGen.wing_weight_of("shore", x, z) < 0.5:
				continue
			var h: float = ART.heights[IslandGen._idx(x, z)]
			var sand: float = ForestGround.sand_weight(float(x), float(z), h)
			var low_edge: bool = h > 0.4 and h <= 1.35
			if h <= 0.4:
				continue  # вода и мокрая кромка: песок там есть, ходить нельзя
			if not low_edge and not (sand >= 0.5 and (x + z) % 4 == 0):
				continue
			assert_true(reach.has(Vector2i(x, z)),
				"пляжная клетка (%d, %d) достижима пешком" % [x, z])
			checked += 1
			if low_edge:
				edge += 1
	assert_gt(checked, 300, "песчаных клеток плато проверено достаточно")
	assert_gt(edge, 20, "низкая полоса у воды проходима")
	var wing_stones := 0
	for stone: Vector3 in data["stones"]:
		if Vector2(stone.x, stone.z).distance_to(WING_CENTER) < 60.0:
			wing_stones += 1
	assert_eq(wing_stones, 1, "камень духа Берега один, на крыле")


func test_shore_landmarks_pair_faces_east() -> void:
	# Пара прибрежных глыб (сборка 4) построена, на крыле, лицом к
	# открытому морю на востоке (общие проверки всех скал — test_cliffs).
	var built: Dictionary = CliffLandmarks.build(ART)
	for type: String in ["lm_shore_north", "lm_shore_south"]:
		assert_true(built["transforms"].has(type), "%s построена" % type)
		var xf: Transform3D = (built["transforms"][type] as Array)[0]
		assert_lt(
			Vector2(xf.origin.x, xf.origin.z).distance_to(WING_CENTER),
			70.0, "%s на крыле Берега" % type)
		var yaw := atan2(-xf.basis.x.z, xf.basis.x.x)
		var face := Vector2(-sin(yaw), -cos(yaw))
		assert_gte(face.dot(Vector2(1.0, 0.0)), 0.7,
			"%s: лицо к восточному морю (dot %.2f)"
				% [type, face.dot(Vector2(1.0, 0.0))])


func test_shore_assets_present() -> void:
	# Меши видов Берега заведены в KINDS и не пустые; текстуры песка
	# на месте (лицензии по каталогу проверяет test_third_party).
	for type: StringName in [
			&"gd_sandrock", &"gd_shell", &"gd_coastrock", &"gd_firepit"]:
		var mesh: Mesh = GroundDetails.kind_mesh(type)
		assert_not_null(mesh, "%s: меш заведён" % type)
		assert_gt(mesh.get_aabb().size.length(), 0.1,
			"%s: меш не пустой" % type)
	for tex: String in [
			"res://assets/third_party/polyhaven.com/coast_sand_01/coast_sand_01_diffuse_2k.jpg",
			"res://assets/third_party/polyhaven.com/coast_sand_01/coast_sand_01_nor_gl_2k.jpg",
			"res://assets/third_party/polyhaven.com/coast_sand_01/coast_sand_01_orm_2k.jpg"]:
		assert_true(ResourceLoader.exists(tex), "текстура песка на месте: %s" % tex)
