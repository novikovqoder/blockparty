# Расширение карты, сборка 2 — биом Утёсов (западное крыло): скальное
# наполнение живёт только на своём крыле (гейтинг по wing_name_at),
# прежние виды с крыльев убраны (кроме папоротника на плато), скальные
# виды поднимаются по кромке выше прежнего предела 15 м, скалы-ориентиры
# CliffLandmarks стоят подножием у моря и лицом к нему, плато красится
# камнем и звучит камнем под ногами. Раскладки детерминированы — два
# построения дают те же трансформы.
extends GutTest

const ART: IslandArt = preload("res://gameplay/world/island_art.res")
const WING_CENTER := Vector2(-170.0, 30.0)

## Скальные виды сборки 2 (поле "zone": "cliffs" в KINDS).
const CLIFF_TYPES: PackedStringArray = [
	"gd_mossrocks1", "gd_mossrocks2", "gd_cliffrock", "gd_rockface1",
	"gd_rockface2", "gd_boulder1", "gd_rock7", "gd_stone1", "gd_rock9",
]
## Прежние виды П12: на крыльях новых земель их быть не должно.
const OLD_TYPES: PackedStringArray = [
	"gd_boulder02", "gd_boulder03", "gd_branch", "gd_debris", "gd_root",
	"gd_roots", "gd_stones", "gd_stump01", "gd_stump02",
]


## Кэш построения HIGH между тестами (build ~3 мин: полный проход 513²).
## Детерминизм в test_cliff_scatter_is_deterministic проверяется двумя
## СВЕЖИМИ построениями — кэш туда не идёт.
var _built_cache: Dictionary = {}
## Кэш данных генератора (generate() ~1.5 мин).
var _gen_cache: Dictionary = {}


func _built() -> Dictionary:
	if _built_cache.is_empty():
		_built_cache = GroundDetails.build(
			ART, GraphicsQuality.Tier.HIGH)
	return _built_cache


func _gen() -> Dictionary:
	if _gen_cache.is_empty():
		_gen_cache = IslandGen.generate()
	return _gen_cache


func test_wing_name_at_splits_island() -> void:
	# Ядро каждого крыла носит своё имя, старый остров (Площадь) — ничьё:
	# гейтинг наполнения опирается на эту функцию.
	assert_eq(IslandGen.wing_name_at(-170, 30), "cliffs", "ядро Утёсов")
	assert_eq(IslandGen.wing_name_at(-130, -130), "thicket", "ядро Чащи")
	assert_eq(IslandGen.wing_name_at(170, -20), "shore", "ядро Прибоя")
	assert_eq(IslandGen.wing_name_at(-10, -160), "meadows", "ядро Лугов")
	assert_eq(IslandGen.wing_name_at(0, 10), "", "Площадь — не крыло")


func test_cliff_kinds_live_only_on_wing() -> void:
	# Все девять скальных видов селятся, заметно (не пара камней) и только
	# в круге крыла Утёсов — не на старом острове и не на чужих крыльях.
	var transforms: Dictionary = _built()["transforms"]
	var wing_span: float = 70.0 + IslandGen.WING_EDGE_BAND + 2.0
	for type: String in CLIFF_TYPES:
		var placed: Array = transforms.get(type, [])
		assert_gt(placed.size(), 10, "%s на крыле Утёсов заметен" % type)
		for xf: Transform3D in placed:
			assert_lt(
				Vector2(xf.origin.x, xf.origin.z).distance_to(WING_CENTER),
				wing_span, "%s не выходит за крыло Утёсов" % type)


func test_old_kinds_leave_wings_except_fern() -> void:
	# Прежние виды убраны с крыльев (крылья ждут своих сборок 3–5);
	# исключение — папоротник на плато Утёсов (мшистая нота).
	var transforms: Dictionary = _built()["transforms"]
	var wings: Array[Vector2] = [
		WING_CENTER, Vector2(-130.0, -130.0), Vector2(170.0, -20.0),
		Vector2(-10.0, -160.0),
	]
	for type: String in OLD_TYPES:
		for xf: Transform3D in transforms.get(type, []):
			for center: Vector2 in wings:
				assert_gt(
					Vector2(xf.origin.x, xf.origin.z).distance_to(center),
					70.0 + IslandGen.WING_EDGE_BAND,
					"%s не селятся на крыле %s" % [type, center])
	var fern_on_cliffs := 0
	for xf: Transform3D in transforms.get("gd_fern", []):
		if Vector2(xf.origin.x, xf.origin.z).distance_to(WING_CENTER) \
				< 70.0:
			fern_on_cliffs += 1
	assert_gt(fern_on_cliffs, 5, "папоротник остался на плато Утёсов")


func test_cliff_kinds_rise_above_old_cap() -> void:
	# Скальные виды идут по кромке выше прежнего предела 15 м — до вершины
	# уступа, но не выше (blocked выше CLIFF_RIM_H + 0.5).
	var transforms: Dictionary = _built()["transforms"]
	var above := 0
	var type: String = "gd_rockface1"
	for t: String in ["gd_rockface1", "gd_rockface2", "gd_cliffrock"]:
		for xf: Transform3D in transforms.get(t, []):
			type = t
			if xf.origin.y > 15.0:
				above += 1
	assert_gt(above, 5, "скальные виды поднимаются по кромке выше 15 м")
	for type2: String in CLIFF_TYPES:
		for xf: Transform3D in transforms.get(type2, []):
			assert_lt(xf.origin.y, IslandGen.CLIFF_RIM_H + 1.0,
				"%s не выше вершины уступа" % type2)


func test_cliff_scatter_is_deterministic() -> void:
	# Два построения дают те же трансформы (свой rng, печёные высоты).
	var first: Dictionary = GroundDetails.build(
		ART, GraphicsQuality.Tier.HIGH)["transforms"]
	var second: Dictionary = GroundDetails.build(
		ART, GraphicsQuality.Tier.HIGH)["transforms"]
	for type: String in CLIFF_TYPES:
		assert_eq(first.get(type, []).size(), second.get(type, []).size(),
			"%s: столько же экземпляров" % type)
		for i: int in (first.get(type, []) as Array).size():
			assert_eq(first[type][i], second[type][i],
				"%s: трансформ %d совпадает" % [type, i])


func test_landmarks_built_face_sea_and_stay_low() -> void:
	# Все скалы-ориентиры находят подножие (нет INF-пропусков), лицом —
	# к морю (локальный −Z наружу от центра крыла), стоят у воды
	# (низко), у каждой — бокс-коллизия.
	var built: Dictionary = CliffLandmarks.build(ART)
	assert_eq((built["instances"] as Array).size(),
		CliffLandmarks.SITES.size(), "все скалы построены")
	assert_eq((built["colliders"] as Array).size(),
		CliffLandmarks.SITES.size(), "у каждой скалы коллизия")
	for type: String in built["transforms"]:
		var xf: Transform3D = (built["transforms"][type] as Array)[0]
		var outward := (
			Vector2(xf.origin.x, xf.origin.z) - WING_CENTER).normalized()
		var yaw := atan2(-xf.basis.x.z, xf.basis.x.x)
		var face := Vector2(-sin(yaw), -cos(yaw))
		assert_gte(face.dot(outward), 0.7,
			"%s: лицо к морю (dot %.2f)" % [type, face.dot(outward)])
		assert_between(xf.origin.y, -4.0, 3.0,
			"%s: подножие у воды (y %.1f)" % [type, xf.origin.y])
		var mesh: Mesh = CliffLandmarks.site_mesh(StringName(type))
		assert_not_null(mesh, "%s: меш по имени" % type)
	assert_null(CliffLandmarks.site_mesh(&"lm_unknown"), "чужое имя — null")


func test_landmarks_deterministic() -> void:
	var first: Dictionary = CliffLandmarks.build(ART)
	var second: Dictionary = CliffLandmarks.build(ART)
	for type: String in first["transforms"]:
		assert_eq(first["transforms"][type][0],
			second["transforms"][type][0], "%s: тот же трансформ" % type)


func test_cliffs_lookouts_on_wing_with_yaw() -> void:
	# Смотровые Утёсов: две, на крыле, уступ 3 м, лестница отвернута
	# от моря (yaw != 0 — свисает к плато).
	var cliffs := 0
	for entry: Dictionary in IslandGen.LOOKOUTS:
		if int(entry["zone"]) != 6:
			continue
		cliffs += 1
		var cell: Vector2i = entry["cell"]
		assert_eq(IslandGen.wing_name_at(cell.x, cell.y), "cliffs",
			"смотровая Утёсов на крыле")
		assert_eq(float(entry["top"]) - float(entry["base"]), 3.0,
			"уступ смотровой 3 м")
		assert_ne(float(entry["ladder_yaw"]), 0.0,
			"лестница смотровой Утёсов повернута")
	assert_eq(cliffs, 2, "на Утёсах две смотровые")
	# poi несёт yaw в игру (generate_island ставит поворот лестницы).
	var data: Dictionary = _gen()
	var yawed := 0
	for poi: Dictionary in data["poi"]["lookouts"]:
		if float(poi.get("yaw", 0.0)) != 0.0:
			yawed += 1
	assert_eq(yawed, 2, "poi: yaw у двух смотровых Утёсов")


func test_cliffs_plateau_paints_and_sounds_stone() -> void:
	# Плато красится скальной подстилкой (вес ≥ 0.5 в ядре крыла) и
	# звучит камнем; старый остров и Лес не тронуты (вес 0).
	var h_center: float = IslandGen.ground_height(
		ART.heights, WING_CENTER.x, WING_CENTER.y)
	assert_gte(ForestGround._cliff_plateau_rock(-170, 30, h_center), 0.5,
		"ядро плато — камень")
	assert_almost_eq(ForestGround._cliff_plateau_rock(0, 4, 10.0), 0.0, 0.001,
		"Площадь не тронута")
	assert_almost_eq(
		ForestGround._cliff_plateau_rock(-40, -40, 10.0), 0.0, 0.001,
		"Лес не тронут")
	assert_eq(ForestGround.surface_kind(
		ART, Vector3(-170.0, h_center, 30.0)), ForestGround.Surface.STONE,
		"под ногами на плато — камень")


func test_cliff_scatter_clear_of_cliffs_lookouts() -> void:
	# Террасы смотровых Утёсов не загорожены твёрдым наполнением
	# (solid_blocked в радиусе 9 м от площадки).
	var transforms: Dictionary = _built()["transforms"]
	var solid_types: PackedStringArray = []
	for kind: Dictionary in GroundDetails.KINDS:
		if kind["solid"] and String(kind.get("zone", "")) == "cliffs":
			solid_types.append(String(kind["type"]))
	assert_gt(solid_types.size(), 0, "твёрдые скальные виды есть")
	for entry: Dictionary in IslandGen.LOOKOUTS:
		if int(entry["zone"]) != 6:
			continue
		var cell: Vector2i = entry["cell"]
		for type: String in solid_types:
			for xf: Transform3D in transforms.get(type, []):
				assert_gt(
					Vector2(xf.origin.x, xf.origin.z).distance_to(
						Vector2(float(cell.x), float(cell.y))),
					9.0, "%s не загораживает террасу %s" % [type, cell])
