# П12 E (SPEC 3.1–3.2): наполнение земли — сканированные CC0-модели
# Poly Haven (валуны, россыпь камней, пни, корни, ветки, щепа, папоротник),
# запечённые в .res с цветом текстуры в вершинах (tools/decimate_polyhaven.gd,
# «ногами» в origin). Раскладка строится в рантайме IslandView._ready по тем
# же правилам, что пропсы IslandGen: клетки 1 × 1 м с джиттером, свой поток
# RandomNumberGenerator (SEED_GROUND_DETAIL) — два построения дают те же
# позиции; island_art.res, генератор и хеш острова не меняются. Плотность:
# Лес (сектор wx < 0, wz < 0) ×FOREST_DENSITY, у руин (радиусы от инстансов
# ruin_* из art.prop_groups) ×RUINS_DENSITY; тропа не загромождается (гашение
# по весу ForestGround), вода, пляж, Площадь, расщелина, причал и дворы
# построек свободны. Коллизия — только крупные (валуны и пни, упрощённый
# бокс по AABB), у мелких — visibility_range и без теней.
# Трава (SPEC 3.2): на HIGH/ULTRA строится рантайм-слой промежуточных пучков
# теми же мешами ForestPlants (GRASS_BOOST_HIGH/ULTRA), тон травы приглушён
# константой GRASS_MUTE в ForestMat — цвет и там, и в печёных пучках один.
class_name GroundDetails
extends RefCounted

## Свой поток rng: печёная раскладка IslandGen не сдвигается.
const SEED_GROUND_DETAIL: int = 20261024
const GRASS_BOOST_SEED: int = 20261025

## Плотность зон (SPEC 3.1: «гуще в Лесу и у руин»).
const FOREST_DENSITY: float = 2.5
const RUINS_DENSITY: float = 2.0
## Плотность лёгкой мелочи во дворе руин (среди кладки, ×1 — без лесной
## множителя): обломки и камешки, не загромождая террасу.
const RUINS_YARD_DENSITY: float = 2.0
## Радиус «у руин» вокруг каждого инстанса ruin_*, м.
const RUINS_NEAR_R: float = 10.0
## Ниже этой отметки (пляж и кромка воды) наполнения нет: песок чистый.
const BEACH_H: float = 1.4
## Отступ лёгкой мелочи от стен руин, м.
const RUINS_CLEAR: float = 2.2

## Константа травы-буста (SPEC 3.2: плотнее в Лесу на HIGH/ULTRA): доля
## клеток с добавочным промежуточным пучком (в пятнах травы, между
## печёными кочками; луга — ×0.4, там травы уже много).
const GRASS_BOOST_HIGH: float = 0.30
const GRASS_BOOST_ULTRA: float = 0.55
const GRASS_MEADOW_FACTOR: float = 0.4

## Прохладный тинт сканов (SPEC 3.7 «приглушённые холодные»): фотосканы
## Полян тёплые, Born Unblessed — холоднее; умножается в вершинный цвет.
const TINT_COOL: Color = Color(0.93, 0.95, 1.03)

## Виды наполнения: p — базовая вероятность на клетку (×плотность зоны),
## scale — диапазон масштаба, range — дальность видимости (м), solid —
## коллизия боксом по AABB, light — можно во двор руин (лёгкая мелочь),
## slope — предельный тангенс уклона, sink — утопление основания (м).
const KINDS: Array[Dictionary] = [
	{
		"type": "gd_boulder02",
		"mesh": preload("res://assets/third_party/polyhaven.com/namaqualand_boulder_02/boulder_02_lo.res"),
		"scale": Vector2(0.7, 1.2), "range": 120.0, "shadow": true,
		"solid": true, "light": false, "slope": 0.55, "sink": 0.16,
		"p": 0.0007,
	},
	{
		"type": "gd_boulder03",
		"mesh": preload("res://assets/third_party/polyhaven.com/namaqualand_boulder_03/boulder_03_lo.res"),
		"scale": Vector2(0.6, 1.1), "range": 120.0, "shadow": true,
		"solid": true, "light": false, "slope": 0.55, "sink": 0.16,
		"p": 0.0007,
	},
	{
		"type": "gd_stones",
		"mesh": preload("res://assets/third_party/polyhaven.com/namaqualand_stones_01/stones_lo.res"),
		"scale": Vector2(0.8, 1.4), "range": 60.0, "shadow": false,
		"solid": false, "light": true, "slope": 0.6, "sink": 0.03,
		"p": 0.0025,
	},
	{
		"type": "gd_stump01",
		"mesh": preload("res://assets/third_party/polyhaven.com/tree_stump_01/stump_01_lo.res"),
		"scale": Vector2(0.8, 1.25), "range": 90.0, "shadow": true,
		"solid": true, "light": false, "slope": 0.5, "sink": 0.08,
		"p": 0.0008,
	},
	{
		"type": "gd_stump02",
		"mesh": preload("res://assets/third_party/polyhaven.com/tree_stump_02/stump_02_lo.res"),
		"scale": Vector2(0.8, 1.25), "range": 90.0, "shadow": true,
		"solid": true, "light": false, "slope": 0.5, "sink": 0.08,
		"p": 0.0008,
	},
	{
		"type": "gd_roots",
		"mesh": preload("res://assets/third_party/polyhaven.com/root_cluster_01/roots_lo.res"),
		"scale": Vector2(0.6, 1.0), "range": 90.0, "shadow": true,
		"solid": false, "light": false, "slope": 0.7, "sink": 0.12,
		"p": 0.001,
	},
	{
		"type": "gd_root",
		"mesh": preload("res://assets/third_party/polyhaven.com/single_root/root_lo.res"),
		"scale": Vector2(0.8, 1.4), "range": 90.0, "shadow": false,
		"solid": false, "light": true, "slope": 0.7, "sink": 0.03,
		"p": 0.003,
	},
	{
		"type": "gd_branch",
		"mesh": preload("res://assets/third_party/polyhaven.com/dry_branches_medium_01/branch_lo.res"),
		"scale": Vector2(0.7, 1.3), "range": 40.0, "shadow": false,
		"solid": false, "light": true, "slope": 0.7, "sink": 0.03,
		"p": 0.007,
	},
	{
		"type": "gd_debris",
		"mesh": preload("res://assets/third_party/polyhaven.com/bark_debris_01/debris_lo.res"),
		"scale": Vector2(0.8, 1.5), "range": 40.0, "shadow": false,
		"solid": false, "light": true, "slope": 0.6, "sink": 0.02,
		"p": 0.004,
	},
	{
		"type": "gd_fern",
		"mesh": preload("res://assets/third_party/polyhaven.com/fern_02/fern_lo.res"),
		"scale": Vector2(0.8, 1.3), "range": 40.0, "shadow": false,
		"solid": false, "light": true, "slope": 0.65, "sink": 0.04,
		"p": 0.004,
	},
]


## Построить наполнение: MultiMeshInstance3D по виду (имя ноды = тип,
## материал, дальность, тени), коллизии крупных и — на HIGH/ULTRA — слой
## травы-буста. Вызывается один раз при входе в мир (смена качества — при
## следующем входе, как у воды); IslandView регистрирует узлы в своей
## таблице дальностей, поэтому «Простая графика»/ULTRA ×1.5 applies и к ним.
static func build(art: IslandArt, tier: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_GROUND_DETAIL
	var ruins := _ruin_positions(art)
	var groups: Dictionary = {}
	for kind: Dictionary in KINDS:
		groups[kind["type"]] = {
			"kind": kind, "transforms": Array(), "colors": PackedColorArray(),
		}
	for z: int in range(-IslandGen.HALF, IslandGen.HALF + 1):
		for x: int in range(-IslandGen.HALF, IslandGen.HALF + 1):
			var cell := _cell_state(art, x, z, ruins)
			if cell["blocked"]:
				continue
			for kind: Dictionary in KINDS:
				_place_kind(groups[kind["type"]], rng, art, x, z, cell, ruins)
	var instances: Array[MultiMeshInstance3D] = []
	var ranges: Dictionary = {}
	var colliders: Array[Dictionary] = []
	var transforms_by_type: Dictionary = {}
	for type: String in groups:
		var group: Dictionary = groups[type]
		var transforms: Array = group["transforms"]
		if transforms.is_empty():
			continue
		var instance := _to_instance(type, group)
		instances.append(instance)
		ranges[type] = group["kind"]["range"]
		# Сырые трансформы — для тестов: в headless инстанс-данные MultiMesh
		# не читаются (пустой RenderingServer), в игре узел полный.
		transforms_by_type[type] = transforms.duplicate()
		if group["kind"]["solid"]:
			for xf: Transform3D in transforms:
				colliders.append(_collider(group["kind"]["mesh"], xf))
	var grass := _build_grass(art, tier)
	for type: String in grass["transforms"]:
		transforms_by_type[type] = (grass["transforms"][type] as Array).duplicate()
	return {
		"instances": instances,
		"ranges": ranges,
		"colliders": colliders,
		"transforms": transforms_by_type,
		"grass": grass["nodes"],
	}


## Попытка поставить один вид в клетке: жёсткие пределы (уклон, двор руин,
## тропа) гасят вероятность до броска, дальше — обычная раскладка «как у
## пропсов»: масштаб, поворот, джиттер, высота билинейной выборкой рельефа.
static func _place_kind(
	group: Dictionary, rng: RandomNumberGenerator, art: IslandArt,
	x: int, z: int, cell: Dictionary, ruins: Array[Vector2],
) -> void:
	var kind: Dictionary = group["kind"]
	if cell["solid_blocked"] and kind["solid"]:
		return
	if cell["slope"] > kind["slope"]:
		return
	var p: float = kind["p"] * cell["density"]
	if cell["yard"]:
		# Двор руин: только лёгкая мелочь среди обломков, не в стенах
		# и не на террасных ступенях кладки.
		if not kind["light"]:
			return
		if not _clear_of_ruins(Vector2(float(x), float(z)), ruins):
			return
		p = kind["p"] * RUINS_YARD_DENSITY
	# Папоротник селят пятна травы (IslandGen._grass_patch — тот же шум,
	# что растит печёные кочки): по пятнам, а не ровным ковром.
	if String(kind["type"]) == "gd_fern":
		var patch: float = IslandGen._grass_patch(x, z)
		p *= (0.3 + 0.7 * patch) if cell["forest"] else 0.3
	# Тропа: плотность гасится — утоптанная земля читается (вес ForestGround).
	p *= 1.0 - cell["path"] * 0.85
	if rng.randf() >= p:
		return
	var scale: float = rng.randf_range(kind["scale"].x, kind["scale"].y)
	var yaw: float = rng.randf_range(0.0, TAU)
	var pos := Vector3(
		x + rng.randf_range(-0.3, 0.3), 0.0, z + rng.randf_range(-0.3, 0.3))
	pos.y = IslandGen.ground_height(art.heights, pos.x, pos.z) \
		- float(kind["sink"]) * scale
	group["transforms"].append(Transform3D(
		Basis(Vector3.UP, yaw) * Basis().scaled(Vector3.ONE * scale), pos))
	var brightness: float = rng.randf_range(0.92, 1.08)
	group["colors"].append(Color(
		TINT_COOL.r * brightness, TINT_COOL.g * brightness,
		TINT_COOL.b * brightness, 1.0))


## Узел вида: MultiMesh с трансформами и instance-тинами, материал
## вершинных цветов (в .res цвет запечён, сканы с атласными UV — ветер
## шейдеров растительности по UV.y к ним неприменим), дальность и тени —
## из таблицы видов.
static func _to_instance(type: String, group: Dictionary) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = group["kind"]["mesh"]
	var transforms: Array = group["transforms"]
	var colors: PackedColorArray = group["colors"]
	mm.instance_count = transforms.size()
	for i: int in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = type
	instance.multimesh = mm
	instance.material_override = LowPolyMat.flat_or_vertex()
	instance.visibility_range_end = float(group["kind"]["range"])
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
		if group["kind"]["shadow"] \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


## Коллизия крупного (SPEC 3.1: только у крупных): бокс по AABB меша
## в масштабе экземпляра, нижняя грань — в основании ({pos, yaw, size},
## формат art.colliders — IslandView._build_colliders ставит так же).
static func _collider(mesh: Mesh, xf: Transform3D) -> Dictionary:
	var aabb: AABB = mesh.get_aabb()
	var scale: float = xf.basis.x.length()
	var yaw := atan2(-xf.basis.x.z, xf.basis.x.x)
	var size := aabb.size * scale
	var center := xf.origin + xf.basis * ((aabb.position + aabb.size * 0.5) * scale)
	return {
		"pos": center - Vector3.UP * size.y * 0.5,
		"yaw": yaw,
		"size": size,
	}


## Слой травы-буста (SPEC 3.2): промежуточные пучки между печёными
## кочками теми же мешами ForestPlants (материал ForestMat — приглушённый
## тон и ветер общие с печёной травой). Только на HIGH/ULTRA; свой поток
## rng — печёная раскладка и детали земли не сдвигаются.
static func _build_grass(art: IslandArt, tier: int) -> Dictionary:
	if tier < GraphicsQuality.Tier.HIGH:
		return {"nodes": [] as Array[MultiMeshInstance3D], "transforms": {}}
	var density: float = GRASS_BOOST_HIGH \
		if tier == GraphicsQuality.Tier.HIGH else GRASS_BOOST_ULTRA
	var rng := RandomNumberGenerator.new()
	rng.seed = GRASS_BOOST_SEED
	var variants: Array[Dictionary] = []
	for variant: int in 3:
		variants.append({
			"mesh": ForestPlants.grass_clump(variant),
			"transforms": Array(),
			"colors": PackedColorArray(),
		})
	for z: int in range(-IslandGen.HALF, IslandGen.HALF + 1):
		for x: int in range(-IslandGen.HALF, IslandGen.HALF + 1):
			var cell := _grass_cell_state(art, x, z)
			if cell["blocked"]:
				continue
			# Гуще в пятнах травы (тот же шум, что печёные кочки), на лугах
			# реже — там и без буста ровный полог.
			var p: float = density * (0.25 + 0.75 * IslandGen._grass_patch(x, z))
			if not cell["forest"]:
				p *= GRASS_MEADOW_FACTOR
			p *= 1.0 - cell["path"] * 0.9
			if rng.randf() >= p:
				continue
			var tufts: int = 1 + (1 if rng.randf() < 0.5 else 0)
			for i: int in tufts:
				var group: Dictionary = variants[rng.randi_range(0, 2)]
				var scale: float = rng.randf_range(0.55, 0.9)
				var yaw: float = rng.randf_range(0.0, TAU)
				var pos := Vector3(
					x + rng.randf_range(-0.45, 0.45), 0.0,
					z + rng.randf_range(-0.45, 0.45))
				pos.y = IslandGen.ground_height(art.heights, pos.x, pos.z)
				group["transforms"].append(Transform3D(
					Basis(Vector3.UP, yaw) * Basis().scaled(Vector3.ONE * scale),
					pos))
				var brightness: float = rng.randf_range(0.92, 1.08)
				group["colors"].append(
					Color(brightness, brightness, brightness, 1.0))
	var nodes: Array[MultiMeshInstance3D] = []
	var transforms_by_type: Dictionary = {}
	for variant: int in variants.size():
		var group: Dictionary = variants[variant]
		if (group["transforms"] as Array).is_empty():
			continue
		transforms_by_type["gd_grass_%d" % variant] = group["transforms"]
		var instance := MultiMeshInstance3D.new()
		instance.name = "gd_grass_%d" % variant
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = group["mesh"]
		var transforms: Array = group["transforms"]
		var colors: PackedColorArray = group["colors"]
		mm.instance_count = transforms.size()
		for i: int in transforms.size():
			mm.set_instance_transform(i, transforms[i])
			mm.set_instance_color(i, colors[i])
		instance.multimesh = mm
		# Тот же материал, что у печёной травы (тон GRASS_MUTE, ветер,
		# спад густоты от камеры); дальность — как у rgrass.
		instance.material_override = ForestMat.for_type(&"rgrass")
		instance.visibility_range_end = PropMeshes.visibility_range(&"rgrass")
		nodes.append(instance)
	return {"nodes": nodes, "transforms": transforms_by_type}


## Состояние клетки для деталей: блокировки (вода/пляж, Площадь, дворы
## построек, каньон расщелины, полоса причала), множитель плотности зоны
## (Лес/руины), уклон и вес тропы — всё детерминировано координатами.
static func _cell_state(
	art: IslandArt, x: int, z: int, ruins: Array[Vector2],
) -> Dictionary:
	var pos := Vector2(float(x), float(z))
	var blocked := false
	var solid_blocked := false
	var h: float = art.heights[IslandGen._idx(x, z)]
	if h <= BEACH_H or h > 15.0:
		blocked = true
	if ForestGround._plaza_weight(pos.x, pos.y) > 0.05 \
			or IslandGen.on_village_pad(pos):
		blocked = true
	if x >= IslandGen.CREVASSE_X0 - 2 and x <= IslandGen.CREVASSE_X1 + 2 \
			and z >= IslandGen.CREVASSE_Z0 - 2 \
			and z <= IslandGen.CREVASSE_Z1 + 2:
		blocked = true  # каньон расщелины и подходы к мосткам
	if x >= 2 and x <= 9 and z >= 56 and z <= 75:
		blocked = true  # полоса причала Озера (подход по берегу)
	var forest := x < 0 and z < 0
	var density := FOREST_DENSITY if forest else 1.0
	if _near_ruins(pos, ruins):
		density = maxf(density, RUINS_DENSITY)
		solid_blocked = true  # у кладки — только лёгкая мелочь
	# Терраса руин (каменные ступени и дворы): тяжёлому нельзя, лёгкому
	# можно с отступом от стен (см. _place_kind).
	var yard := pos.distance_to(Vector2(58.0, -48.0)) < 21.0
	if yard:
		solid_blocked = true
	return {
		"blocked": blocked,
		"solid_blocked": solid_blocked,
		"yard": yard,
		"forest": forest,
		"density": density,
		"slope": ForestGround._slope(art, x + IslandGen.HALF, z + IslandGen.HALF),
		"path": maxf(
			ForestGround._path_weight(pos.x, pos.y),
			ForestGround._plaza_weight(pos.x, pos.y)),
	}


## Состояние клетки для травы-буста: те же блокировки плюс «не на тропе»
## и уклон по _is_grassy_forest (на камне травы нет).
static func _grass_cell_state(art: IslandArt, x: int, z: int) -> Dictionary:
	var pos := Vector2(float(x), float(z))
	var blocked := false
	var h: float = art.heights[IslandGen._idx(x, z)]
	if h <= 1.0 or h > 15.0:
		blocked = true
	if ForestGround._plaza_weight(pos.x, pos.y) > 0.05 \
			or IslandGen.on_village_pad(pos):
		blocked = true
	if pos.distance_to(Vector2(58.0, -48.0)) < 25.0:
		blocked = true  # терраса руин — камень
	if x >= IslandGen.CREVASSE_X0 - 2 and x <= IslandGen.CREVASSE_X1 + 2 \
			and z >= IslandGen.CREVASSE_Z0 - 2 \
			and z <= IslandGen.CREVASSE_Z1 + 2:
		blocked = true
	if x >= 2 and x <= 9 and z >= 56 and z <= 75:
		blocked = true
	var slope: float = ForestGround._slope(
		art, x + IslandGen.HALF, z + IslandGen.HALF)
	if slope >= 0.7:
		blocked = true  # тот же предел, что у печёных кочек
	var path: float = ForestGround._path_weight(pos.x, pos.y)
	if path >= 0.2:
		blocked = true  # тропа читается землёй, как у печёной травы
	return {
		"blocked": blocked,
		"forest": x < 0 and z < 0,
		"path": path,
	}


## Позиции кладки руин из запечённого острова (SPEC 3.1 «гуще у руин» —
## радиусы от самих инстансов ruin_*).
static func _ruin_positions(art: IslandArt) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for key: String in art.prop_groups:
		if not key.begins_with("ruin"):
			continue
		var group: PropGroup = art.prop_groups[key]
		for xf: Transform3D in group.transforms:
			positions.append(Vector2(xf.origin.x, xf.origin.z))
	return positions


static func _near_ruins(pos: Vector2, ruins: Array[Vector2]) -> bool:
	for ruin: Vector2 in ruins:
		if pos.distance_to(ruin) <= RUINS_NEAR_R:
			return true
	return false


static func _clear_of_ruins(pos: Vector2, ruins: Array[Vector2]) -> bool:
	for ruin: Vector2 in ruins:
		if pos.distance_to(ruin) <= RUINS_CLEAR:
			return false
	return true
