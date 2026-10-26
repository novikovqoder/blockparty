# П14 3.3: слой мелочи вокруг игрока — камешки, сухие веточки, щепа/листва
# и мелкие пучки травы (MultiMesh, без коллизии, тени только на ULTRA).
# В отличие от наполнения GroundDetails (весь остров, строится один раз),
# мелочь живёт кольцом вокруг зрителя: IslandView.update_viewer снапит
# центр на клетку CELL_M и пересобирает буферы. Детерминизм — по мировым
# клеткам: содержимое клетки 1 × 1 м выводится из её собственного seed
# (целочисленный кортеж-хеш координат + SEED_CLUTTER), поэтому порядок
# обхода и повторные пересборки дают те же позиции; печёная раскладка
# IslandGen/GroundDetails не сдвигается. Плотность HIGH = ½ ULTRA,
# к кромке кольца плотность спадает. Шишек в скачанных наборах нет
# (в STATUS); модели — уже используемые .res Poly Haven и пучки
# ForestPlants, новых скачиваний нет.
class_name GroundClutter
extends RefCounted

## Свой seed слоя (не пересекается с потоками IslandGen/GroundDetails).
const SEED_CLUTTER: int = 20261026
## Радиус кольца мелочи, м (SPEC П14 3.3: 15–25 м).
const RADIUS: float = 20.0
## Клетка пересборки вокруг игрока, м (снап IslandView).
const CELL_M: float = 4.0
## Полоса спада плотности у кромки, м.
const EDGE_FADE: float = 4.0
## Плотность на клетку 1 × 1 м суммарно: ULTRA и HIGH = ½ (SPEC П14 3.3).
const DENSITY_ULTRA: float = 1.0
const DENSITY_HIGH: float = 0.5
## Гуще в Лесу (как наполнение), реже на открытых лугах.
const FOREST_DENSITY: float = 1.6
const MEADOW_DENSITY: float = 0.7
## Ниже этой отметки (пляж и кромка воды) мелочи нет: песок чистый,
## как у наполнения.
const BEACH_H: float = 1.4
## Терраса руин — камень: центр и радиус чистой зоны (тот же, что у
## наполнения; 21 у клеток, 20.5 у самих точек — запас на дрожание).
const RUIN_CENTER: Vector2 = Vector2(58.0, -48.0)
const RUIN_CLEAR: float = 20.5
## Прохладный тинт сканов — общий с GroundDetails.
const TINT_COOL: Color = Color(0.93, 0.95, 1.03)

## Виды мелочи: share — доля суммарной плотности, scale — диапазон
## масштаба, slope — предельный уклон, sink — утопление основания (м),
## grass — селиться пятнами травы (пучки), mesh/material ставит
## make_nodes (пучкам — материал травы с ветром).
const KINDS: Array[Dictionary] = [
	{
		"type": "gc_stone",
		"scale": Vector2(0.5, 0.9), "slope": 0.6, "sink": 0.03,
		"share": 0.30, "grass": false,
	},
	{
		"type": "gc_branch",
		"scale": Vector2(0.55, 0.95), "slope": 0.7, "sink": 0.03,
		"share": 0.14, "grass": false,
	},
	{
		"type": "gc_debris",
		"scale": Vector2(0.6, 1.1), "slope": 0.6, "sink": 0.02,
		"share": 0.20, "grass": false,
	},
	{
		"type": "gc_tuft0",
		"scale": Vector2(0.4, 0.7), "slope": 0.7, "sink": 0.04,
		"share": 0.12, "grass": true,
	},
	{
		"type": "gc_tuft1",
		"scale": Vector2(0.4, 0.7), "slope": 0.7, "sink": 0.04,
		"share": 0.12, "grass": true,
	},
	{
		"type": "gc_tuft2",
		"scale": Vector2(0.4, 0.7), "slope": 0.7, "sink": 0.04,
		"share": 0.12, "grass": true,
	},
]


## Меш вида: сканы — preload-константы, пучки травы — процедурные
## ForestPlants (вызов функции, поэтому не в const-таблице).
static func kind_mesh(type: String) -> Mesh:
	match type:
		"gc_stone":
			return preload("res://assets/third_party/polyhaven.com/namaqualand_stones_01/stones_lo.res")
		"gc_branch":
			return preload("res://assets/third_party/polyhaven.com/dry_branches_medium_01/branch_lo.res")
		"gc_debris":
			return preload("res://assets/third_party/polyhaven.com/bark_debris_01/debris_lo.res")
		"gc_tuft0":
			return ForestPlants.grass_clump(0)
		"gc_tuft1":
			return ForestPlants.grass_clump(1)
		_:
			return ForestPlants.grass_clump(2)


## Мелочь включена на HIGH/ULTRA (SPEC П14 3.3: ниже — как раньше).
static func is_clutter_enabled(tier: int) -> bool:
	return tier >= GraphicsQuality.Tier.HIGH


## Плотность слоя для уровня (HIGH = ½ ULTRA).
static func density_for_tier(tier: int) -> float:
	return DENSITY_HIGH if tier == GraphicsQuality.Tier.HIGH \
		else DENSITY_ULTRA


## Seed мировой клетки 1 × 1 м: целочисленный кортеж-хеш — одна и та же
## клетка всегда даёт тот же поток, независимо от порядка пересборки.
static func cell_seed(x: int, z: int) -> int:
	return (SEED_CLUTTER ^ (x * 73856093) ^ (z * 19349663)) & 0x7fffffff


## Ноды мелочи по видам (меш, материал, тени по уровню; пучки — материал
## травы с ветром и общим тоном). Буферы пустые — заполняет update.
static func make_nodes(tier: int) -> Dictionary:
	var nodes: Dictionary = {}
	for kind: Dictionary in KINDS:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = kind_mesh(String(kind["type"]))
		var instance := MultiMeshInstance3D.new()
		instance.name = String(kind["type"])
		instance.multimesh = mm
		instance.material_override = ForestMat.for_type(&"rgrass") \
			if kind["grass"] else LowPolyMat.flat_or_vertex()
		# Тени — только ULTRA (SPEC П14 3.3): мелочь на HIGH дешевле.
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
			if tier == GraphicsQuality.Tier.ULTRA \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		nodes[kind["type"]] = instance
	return nodes


## Разложить мелочь вокруг center (мировые метры): чистая функция —
## возвращает трансформы и цвета по типам; IslandView.apply_clutter
## переносит их в MultiMesh, тесты читают напрямую.
static func scatter(
	art: IslandArt, tier: int, center: Vector2,
) -> Dictionary:
	var density := density_for_tier(tier)
	var groups: Dictionary = {}
	for kind: Dictionary in KINDS:
		groups[kind["type"]] = {
			"kind": kind, "transforms": Array(), "colors": PackedColorArray(),
		}
	var r_cells: int = int(ceilf(RADIUS))
	var cx: int = roundi(center.x)
	var cz: int = roundi(center.y)
	for z: int in range(cz - r_cells, cz + r_cells + 1):
		for x: int in range(cx - r_cells, cx + r_cells + 1):
			var dist: float = Vector2(float(x), float(z)).distance_to(center)
			if dist > RADIUS:
				continue
			# За картой высот (остров — мир ±HALF) мелочи нет — и чтения
			# высот в _cell_blocked/_slope не выходят за массив, когда
			# наблюдатель (камера) ушёл за край острова.
			if absi(x) > IslandGen.HALF or absi(z) > IslandGen.HALF:
				continue
			if _cell_blocked(art, x, z):
				continue
			# Спад плотности к кромке: у края кольца мелочь редеет, стык
			# с «пустым» дальним планом не читается полосой.
			var edge: float = clampf(
				(RADIUS - dist) / EDGE_FADE, 0.0, 1.0)
			var zone: float = FOREST_DENSITY \
				if x < 0 and z < 0 else MEADOW_DENSITY
			var path: float = maxf(
				ForestGround._path_weight(float(x), float(z)),
				ForestGround._plaza_weight(float(x), float(z)))
			var slope: float = ForestGround._slope(
				art, x + IslandGen.HALF, z + IslandGen.HALF)
			# Свой поток на клетку — детерминизм по мировым координатам.
			var rng := RandomNumberGenerator.new()
			rng.seed = cell_seed(x, z)
			for kind: Dictionary in KINDS:
				if slope > float(kind["slope"]):
					continue  # камешки ровнее, ветки и пучки держат склон
				var p: float = density * float(kind["share"]) * zone * edge
				p *= 1.0 - path * 0.85
				if kind["grass"]:
					# Пучки — пятнами травы (тот же шум, что печёные кочки).
					p *= 0.25 + 0.75 * IslandGen._grass_patch(x, z)
				if rng.randf() >= p:
					continue
				var group: Dictionary = groups[kind["type"]]
				var scale: float = rng.randf_range(
					float(kind["scale"].x), float(kind["scale"].y))
				var yaw: float = rng.randf_range(0.0, TAU)
				var pos := Vector3(
					x + rng.randf_range(-0.45, 0.45), 0.0,
					z + rng.randf_range(-0.45, 0.45))
				# Клетки блокируются по центру (_cell_blocked), но позиция
				# дрожит до ±0.64 м по диагонали — запретные зоны (дворы,
				# Площадь, терраса руин) проверяем и самой точкой.
				var pos2 := Vector2(pos.x, pos.z)
				if IslandGen.on_village_pad(pos2):
					continue
				if ForestGround._plaza_weight(pos2.x, pos2.y) > 0.05:
					continue
				if pos2.distance_to(RUIN_CENTER) < RUIN_CLEAR:
					continue
				pos.y = IslandGen.ground_height(
					art.heights, pos.x, pos.z) \
					- float(kind["sink"]) * scale
				# Дрожание вниз по склону может опустить точку на пляж —
				# кромка воды остаётся чистой (BEACH_H из _cell_blocked).
				if pos.y <= BEACH_H:
					continue
				(group["transforms"] as Array).append(Transform3D(
					Basis(Vector3.UP, yaw) * Basis().scaled(Vector3.ONE * scale),
					pos))
				var brightness: float = rng.randf_range(0.92, 1.08)
				# Без as-каста (идиома GroundDetails): каст создаёт копию
				# COW-массива, append уходил в никуда — цвета не доезжали
				# до apply_clutter, и он падал на пустом PackedColorArray.
				if kind["grass"]:
					group["colors"].append(Color(
						brightness, brightness, brightness, 1.0))
				else:
					group["colors"].append(Color(
						TINT_COOL.r * brightness, TINT_COOL.g * brightness,
						TINT_COOL.b * brightness, 1.0))
	return groups


## Блокировки клетки: вода/пляж, Площадь, дворы построек, каньон, полоса
## причала, терраса руин — те же зоны, что свободны от наполнения
## (GroundDetails._grass_cell_state); уклон трогает только пределы видов
## (см. scatter), тропа не блокируется, а гасит плотность.
static func _cell_blocked(art: IslandArt, x: int, z: int) -> bool:
	if art.heights[IslandGen._idx(x, z)] <= BEACH_H:
		return true
	var pos := Vector2(float(x), float(z))
	if ForestGround._plaza_weight(pos.x, pos.y) > 0.05:
		return true
	if IslandGen.on_village_pad(pos):
		return true
	if pos.distance_to(RUIN_CENTER) < 21.0:
		return true  # терраса руин — камень
	if x >= IslandGen.CREVASSE_X0 - 2 and x <= IslandGen.CREVASSE_X1 + 2 \
			and z >= IslandGen.CREVASSE_Z0 - 2 \
			and z <= IslandGen.CREVASSE_Z1 + 2:
		return true
	return x >= 2 and x <= 9 and z >= 56 and z <= 75


## Перенести раскладку scatter в ноды (буферы MultiMesh целиком).
static func apply_clutter(
	nodes: Dictionary, groups: Dictionary,
) -> void:
	for type: String in nodes:
		var instance: MultiMeshInstance3D = nodes[type]
		var group: Dictionary = groups.get(type, {})
		var transforms: Array = group.get("transforms", [])
		var mm: MultiMesh = instance.multimesh
		mm.instance_count = transforms.size()
		var colors: PackedColorArray = group.get(
			"colors", PackedColorArray())
		for i: int in transforms.size():
			mm.set_instance_transform(i, transforms[i])
			mm.set_instance_color(i, colors[i])
