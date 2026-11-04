# П17, сборка 3 (пункты 6–8 плана docs/gfx_trees/PLAN_p17.md): поле
# фотосканной травы вокруг игрока — пучки/цветы/папоротники Poly Haven
# (децимированы bundle-режимом tools/decimate_polyhaven.gd, цвет в вершинах).
# По образцу GroundClutter: MultiMesh по видам, пересборка при уходе зрителя
# на клетку CELL_M, детерминизм по мировым клеткам — свой seed на клетку
# 1 × 1 м (тот же кортеж-хеш, что у мелочи, с SEED_GRASS_FIELD), поэтому
# повторные проходы и оба уровня качества дают одну и ту же раскладку
# клетки (бросок rng потребляется всегда, сравнение с вероятностью — после;
# радиус и плотность меняют только охват и отсечку). Печёная подложка
# ForestPlants (rgrass) остаётся — поле садится поверх.
# Зоны — те же, что у травы-буста (GroundDetails._grass_cell_state): вода/
# пляж, Площадь, дворы построек, терраса руин, каньон, причал, тропа и
# крутая скала. Луга и опушки гуще (×MEADOW_DENSITY), глубина Леса реже
# (×FOREST_DENSITY) — там поле сменяется подстилкой с папоротниками у
# стволов (etree_* из art.prop_groups, пространственная сетка). Цветы —
# пятнами своего шума, вид пятна детерминирован крупной клеткой (два вида
# не смешиваются); bermuda — низкая трава у троп (решение владельца:
# плотность растёт с весом тропы, на самом гравии блок).
class_name GrassField
extends RefCounted

const SHADER: Shader = preload("res://assets/shaders/grass_scan.gdshader")

## Свой seed слоя (не пересекается с мелочью и наполнением).
const SEED_GRASS_FIELD: int = 20261104
## Клетка пересборки вокруг игрока, м (снап IslandView.update_viewer).
const CELL_M: float = 8.0
## Радиус поля по уровню, м (П17 п.13: ULTRA ~45, HIGH ~30).
const RADIUS_ULTRA: float = 45.0
const RADIUS_HIGH: float = 30.0
## Базовая плотность пучков на клетку 1 × 1 м (суммарно по видам, ULTRA);
## HIGH = ½ (П17 п.13).
const BASE_DENSITY: float = 0.30
const DENSITY_HIGH: float = 0.5
## Кромка поля: последние метры радиуса масштаб пучков плавно к нулю
## (П17 п.8) — стык с пустым дальним планом не читается полосой.
const EDGE_M: float = 3.0
## Луга/опушки гуще, глубина Леса реже (П17 п.6).
const MEADOW_DENSITY: float = 1.6
const FOREST_DENSITY: float = 0.6
## Ниже этой отметки (после дрожания точки) травы нет: песок чистый.
const BEACH_H: float = 1.4
## Дрожание наклона пучка от нормали рельефа, рад.
const TILT_MAX: float = 0.175  # ~10°
## Пятна цветов: свой шум (не кочки), внутри пятна плотность ×FLOWER_BOOST,
## вне — ×FLOWER_FADE; вид пятна — по крупной клетке FLOWER_CELL м.
const FLOWER_SEED: int = 20261105
const FLOWER_FREQUENCY: float = 0.055
const FLOWER_FROM: float = 0.60
const FLOWER_TO: float = 0.68
const FLOWER_BOOST: float = 6.0
const FLOWER_FADE: float = 0.2
const FLOWER_CELL: float = 16.0
## Папоротники тени Леса: множитель плотности у стволов (в радиусе
## TRUNK_NEAR) и в остальном лесу.
const FERN_TRUNK_BOOST: float = 2.2
const FERN_FOREST_FACTOR: float = 0.8
const TRUNK_NEAR: float = 5.0
## Клетка пространственной сетки стволов (достаточно 9 соседних).
const TRUNK_CELL: float = 8.0
## Ближнее кольцо теней (П17 п.13): на ULTRA поле разбито на две ноды
## на вид — ближняя (≤ SHADOW_RING_M, cast_shadow ON) и дальняя (без
## теней); на HIGH поле целиком без теней.
const SHADOW_RING_M: float = 10.0

## Виды поля: share — доля базовой плотности, scale — диапазон масштаба
## (0.7–1.4, «разной высоты» референса), slope — предельный уклон,
## sink — утопление основания (м), mode — поведение раскладки
## (grass/flower/fern/bermuda). Треугольники пучков (план п.5: пучки
## ~1.5–3k, цветы ~1–2k) выверены под бюджет: тяжёлые large/mid — реже,
## лёгкий tall — основной, кочки bermuda — почти бесплатны.
const KINDS: Array[Dictionary] = [
	{
		"type": "gf_large", "mode": "grass",
		"mesh": preload("res://assets/third_party/polyhaven.com/grass_medium_01/grass_m1_large.res"),
		"scale": Vector2(0.8, 1.3), "slope": 0.65, "sink": 0.02,
		"share": 0.08,
	},
	{
		"type": "gf_mid", "mode": "grass",
		"mesh": preload("res://assets/third_party/polyhaven.com/grass_medium_01/grass_m1_mid.res"),
		"scale": Vector2(0.8, 1.3), "slope": 0.65, "sink": 0.02,
		"share": 0.08,
	},
	{
		"type": "gf_tall", "mode": "grass",
		"mesh": preload("res://assets/third_party/polyhaven.com/grass_medium_01/grass_m1_tall.res"),
		"scale": Vector2(0.85, 1.4), "slope": 0.65, "sink": 0.02,
		"share": 0.20,
	},
	{
		"type": "gf_small", "mode": "grass",
		"mesh": preload("res://assets/third_party/polyhaven.com/grass_medium_01/grass_m1_small.res"),
		"scale": Vector2(0.7, 1.1), "slope": 0.7, "sink": 0.02,
		"share": 0.16,
	},
	{
		"type": "gf_m2", "mode": "grass",
		"mesh": preload("res://assets/third_party/polyhaven.com/grass_medium_02/grass_m2.res"),
		"scale": Vector2(0.7, 1.2), "slope": 0.65, "sink": 0.02,
		"share": 0.12,
	},
	{
		"type": "gf_bermuda", "mode": "bermuda",
		"mesh": preload("res://assets/third_party/polyhaven.com/grass_bermuda_01/bermuda_medium.res"),
		"scale": Vector2(0.9, 1.4), "slope": 0.7, "sink": 0.01,
		"share": 0.25,
	},
	{
		"type": "gf_celandine", "mode": "flower",
		"mesh": preload("res://assets/third_party/polyhaven.com/celandine_01/celandine.res"),
		"scale": Vector2(0.8, 1.3), "slope": 0.6, "sink": 0.02,
		"share": 0.05,
	},
	{
		"type": "gf_dandelion", "mode": "flower",
		"mesh": preload("res://assets/third_party/polyhaven.com/dandelion_01/dandelion.res"),
		"scale": Vector2(0.8, 1.3), "slope": 0.6, "sink": 0.02,
		"share": 0.05,
	},
	{
		"type": "gf_fern", "mode": "fern",
		"mesh": preload("res://assets/third_party/polyhaven.com/fern_02/fern_lo.res"),
		"scale": Vector2(0.8, 1.3), "slope": 0.65, "sink": 0.04,
		"share": 0.06,
	},
]


## Поле включено на HIGH/ULTRA (как мелочь и трава-буст; SIMPLE/NORMAL —
## печёная подложка rgrass, как раньше).
static func is_field_enabled(tier: int) -> bool:
	return tier >= GraphicsQuality.Tier.HIGH


## Радиус поля для уровня, м.
static func radius_for_tier(tier: int) -> float:
	return RADIUS_ULTRA if tier == GraphicsQuality.Tier.ULTRA \
		else RADIUS_HIGH


## Плотность слоя для уровня (HIGH = ½ ULTRA, П17 п.13).
static func density_for_tier(tier: int) -> float:
	return DENSITY_HIGH if tier == GraphicsQuality.Tier.HIGH else 1.0


## Seed мировой клетки 1 × 1 м: та же схема, что у GroundClutter, со своим
## seed слоя — одна и та же клетка всегда даёт тот же поток.
static func cell_seed(x: int, z: int) -> int:
	return (SEED_GRASS_FIELD ^ (x * 73856093) ^ (z * 19349663)) & 0x7fffffff


## Наклон нормали рельефа в точке (полуметровые разности билинейной выборки
## — сглаженная нормаль, как карта нормалей ForestGround).
static func ground_normal(art: IslandArt, fx: float, fz: float) -> Vector3:
	var dx: float = IslandGen.ground_height(art.heights, fx + 0.5, fz) \
		- IslandGen.ground_height(art.heights, fx - 0.5, fz)
	var dz: float = IslandGen.ground_height(art.heights, fx, fz + 0.5) \
		- IslandGen.ground_height(art.heights, fx, fz - 0.5)
	return Vector3(-dx, 1.0, -dz).normalized()


## Вид цветов крупной клетки пятна: celandine или dandelion — детерминирован
## координатами, в одном пятне виды не смешиваются (П17 п.6).
static func flower_kind_for(x: int, z: int) -> String:
	var cell: int = (SEED_GRASS_FIELD + 1) \
		^ (int(floorf(float(x) / FLOWER_CELL)) * 2654435761) \
		^ (int(floorf(float(z) / FLOWER_CELL)) * 40503)
	return "gf_dandelion" if cell & 1 != 0 else "gf_celandine"


## Пространственная сетка стволов etree_* (клетки TRUNK_CELL м) — «гуще
## у стволов» без прохода по всем деревьям на каждую клетку поля.
static func trunk_grid(art: IslandArt) -> Dictionary:
	var grid: Dictionary = {}
	for key: String in art.prop_groups:
		if not key.begins_with("etree_"):
			continue
		var group: PropGroup = art.prop_groups[key]
		for xf: Transform3D in group.transforms:
			var cell := Vector2i(
				int(floorf(xf.origin.x / TRUNK_CELL)),
				int(floorf(xf.origin.z / TRUNK_CELL)))
			if not grid.has(cell):
				grid[cell] = [] as Array[Vector2]
			(grid[cell] as Array[Vector2]).append(
				Vector2(xf.origin.x, xf.origin.z))
	return grid


## Есть ли ствол в радиусе TRUNK_NEAR (просмотр 9 соседних клеток сетки).
static func near_trunk(grid: Dictionary, x: float, z: float) -> bool:
	var base := Vector2i(
		int(floorf(x / TRUNK_CELL)), int(floorf(z / TRUNK_CELL)))
	for cell_x: int in range(base.x - 1, base.x + 2):
		for cell_z: int in range(base.y - 1, base.y + 2):
			var trunks: Array = grid.get(Vector2i(cell_x, cell_z), [])
			for trunk: Vector2 in trunks:
				if Vector2(x, z).distance_to(trunk) <= TRUNK_NEAR:
					return true
	return false


## Ноды поля по видам (меш, материал с ветром/приминанием). На ULTRA у
## вида две ноды: ближняя «<вид>_near» (≤ SHADOW_RING_M, с тенями) и
## дальняя без теней (П17 п.13); на HIGH — одна, без теней. Буферы
## пустые — заполняет apply_field из scatter.
static func make_nodes(tier: int) -> Dictionary:
	var nodes: Dictionary = {}
	var material := _material(tier)
	for kind: Dictionary in KINDS:
		var type := String(kind["type"])
		nodes[type] = _make_node(type, kind["mesh"], material, false)
		if tier == GraphicsQuality.Tier.ULTRA:
			nodes[type + "_near"] = _make_node(
				type + "_near", kind["mesh"], material, true)
	return nodes


static func _make_node(
		type: String, mesh: Mesh, material: Material, shadow: bool
) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	var instance := MultiMeshInstance3D.new()
	instance.name = type
	instance.multimesh = mm
	instance.material_override = material
	# Тени поля — только ближняя нода ULTRA (П17 п.13).
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
		if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


## Материал поля: один на все виды (вариации — инстанс-цвета). В headless
## шейдер не компилируется — плоский вершинно-цветной, как ForestMat.
## Спад густоты (fade) — от радиуса уровня: кромка «садится» в землю.
static func _material(tier: int) -> Material:
	if WorldMaterials.want_flat():
		return LowPolyMat.flat_or_vertex()
	var radius := radius_for_tier(tier)
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("fade_start", radius * 0.55)
	material.set_shader_parameter("fade_end", radius * 0.92)
	return material


## Разложить поле вокруг center (мировые метры): чистая функция —
## трансформы и цвета по видам; IslandView.apply_field переносит их в
## MultiMesh, тесты читают напрямую.
static func scatter(art: IslandArt, tier: int, center: Vector2) -> Dictionary:
	var density := BASE_DENSITY * density_for_tier(tier)
	var radius := radius_for_tier(tier)
	var groups: Dictionary = {}
	for kind: Dictionary in KINDS:
		groups[kind["type"]] = {
			"kind": kind, "transforms": Array(), "colors": PackedColorArray(),
		}
	var flower_patch := FastNoiseLite.new()
	flower_patch.seed = FLOWER_SEED
	flower_patch.frequency = FLOWER_FREQUENCY
	var trunks := trunk_grid(art)
	var r_cells: int = int(ceilf(radius))
	var cx: int = roundi(center.x)
	var cz: int = roundi(center.y)
	for z: int in range(cz - r_cells, cz + r_cells + 1):
		for x: int in range(cx - r_cells, cx + r_cells + 1):
			var dist: float = Vector2(float(x), float(z)).distance_to(center)
			if dist > radius:
				continue
			# За картой высот поля нет — и чтения высот не выходят за массив.
			if absi(x) > IslandGen.HALF or absi(z) > IslandGen.HALF:
				continue
			var cell := GroundDetails._grass_cell_state(art, x, z)
			if cell["blocked"]:
				continue
			# Зона: луга ×1.6; в Лесу — от кромки (как опушка) вглубь к ×0.6.
			var zone: float = MEADOW_DENSITY
			if cell["forest"]:
				zone = lerpf(MEADOW_DENSITY, FOREST_DENSITY, clampf(
					ForestGround._forest_edge_dist(float(x), float(z))
					/ ForestGround.EDGE_SOFT, 0.0, 1.0))
			# Тропа: гравий читается — плотность плавно гаснет к блоку
			# (в blocked у самой полосы; bermuda — наоборот, см. ниже).
			var path: float = cell["path"]
			var path_fade: float = 1.0 - clampf(
				(path - 0.05) / 0.15, 0.0, 1.0) * 0.9
			# Скала: от мягкого уклона плотность плавно падает к нулю
			# (жёсткий блок — в _grass_cell_state, slope >= 0.7).
			var slope: float = ForestGround._slope(
				art, x + IslandGen.HALF, z + IslandGen.HALF)
			var rock_fade: float = 1.0 - smoothstep(
				ForestGround.ROCK_SLOPE_SOFT,
				ForestGround.ROCK_SLOPE_FULL, slope) * 0.9
			# Пятна и проплешины: тот же шум, что печёные кочки и буст.
			var patch: float = IslandGen._grass_patch(x, z)
			# Свой поток на клетку — детерминизм по мировым координатам.
			var rng := RandomNumberGenerator.new()
			rng.seed = cell_seed(x, z)
			for kind: Dictionary in KINDS:
				var mode := String(kind["mode"])
				# Папоротник — только тень Леса (x < 0, z < 0).
				if mode == "fern" and not cell["forest"]:
					continue
				var p: float = density * float(kind["share"]) \
					* zone * path_fade * rock_fade
				p *= 0.25 + 0.75 * patch
				if mode == "flower":
					# Пятна цветов: свой шум; вид пятна детерминирован
					# крупной клеткой — два вида не смешиваются.
					var fp: float = smoothstep(
						FLOWER_FROM, FLOWER_TO,
						(flower_patch.get_noise_2d(x, z) + 1.0) * 0.5)
					p *= lerpf(FLOWER_FADE, FLOWER_BOOST, fp)
					if flower_kind_for(x, z) != String(kind["type"]):
						continue
				elif mode == "bermuda":
					# Низкая трава у троп и вытоптанных мест (решение
					# владельца): гуще к кромке гравия.
					p *= lerpf(0.4, 3.0, path)
				elif mode == "fern":
					p *= FERN_TRUNK_BOOST if near_trunk(
						trunks, float(x), float(z)) else FERN_FOREST_FACTOR
				if slope > float(kind["slope"]):
					continue
				# Бросок потребляется всегда — поток rng не зависит от
				# уровня качества (радиус/плотность), только охват клеток.
				var roll: float = rng.randf()
				if roll >= p:
					continue
				var scale: float = rng.randf_range(
					float(kind["scale"].x), float(kind["scale"].y))
				# Кромка поля: масштаб пучка плавно к нулю (П17 п.8),
				# плотность у края не гасится.
				var edge: float = clampf((radius - dist) / EDGE_M, 0.0, 1.0)
				scale *= edge
				if scale < 0.005:
					continue
				var pos := Vector3(
					x + rng.randf_range(-0.45, 0.45), 0.0,
					z + rng.randf_range(-0.45, 0.45))
				var pos2 := Vector2(pos.x, pos.z)
				# Дрожание вниз по склону не должно заносить пучок
				# в запретные зоны (как у мелочи П14 3.3).
				if IslandGen.on_village_pad(pos2):
					continue
				if ForestGround._plaza_weight(pos2.x, pos2.y) > 0.05:
					continue
				pos.y = IslandGen.ground_height(
					art.heights, pos.x, pos.z) - float(kind["sink"]) * scale
				if pos.y <= BEACH_H:
					continue
				# Посадка: нормаль рельефа + произвольный yaw + дрожание
				# наклона до 10°; масштаб — равномерный по осям.
				var yaw: float = rng.randf_range(0.0, TAU)
				var tilt_axis := Vector3(
					rng.randf_range(-1.0, 1.0), 0.0,
					rng.randf_range(-1.0, 1.0)).normalized()
				var basis := Basis(
					Quaternion(Vector3.UP, ground_normal(art, pos.x, pos.z))) \
					* Basis(Vector3.UP, yaw) \
					* Basis(tilt_axis, rng.randf_range(0.0, TILT_MAX))
				var group: Dictionary = groups[kind["type"]]
				(group["transforms"] as Array).append(Transform3D(
					basis * Basis().scaled(Vector3.ONE * scale), pos))
				var brightness: float = rng.randf_range(0.92, 1.08)
				# Цветки чуть теплее тона скана (П17 п.6).
				if mode == "flower":
					group["colors"].append(Color(
						brightness * 1.05, brightness * 0.99,
						brightness * 0.94, 1.0))
				else:
					group["colors"].append(Color(
						brightness, brightness, brightness, 1.0))
	return groups


## Перенести раскладку scatter в ноды (буферы MultiMesh целиком). center —
## центр раскладки: на ULTRA ближние инстансы (≤ SHADOW_RING_M) идут в
## ноду с тенями «<вид>_near», остальные — в основную; без near-пары
## (HIGH) всё ложится в основную.
static func apply_field(
		nodes: Dictionary, groups: Dictionary, center: Vector2
) -> void:
	for type: String in nodes:
		if type.ends_with("_near"):
			continue  # заполняется из раскладки базового вида
		var instance: MultiMeshInstance3D = nodes[type]
		var group: Dictionary = groups.get(type, {})
		var transforms: Array = group.get("transforms", [])
		if not transforms.is_empty() and nodes.has(type + "_near"):
			# Разбивка вынесена в чистую функцию: буферы мультимеша в
			# headless не читаются (get_instance_transform — identity),
			# тест проверяет принадлежность по раскладке scatter.
			var split := near_far_indices(transforms, center)
			_fill_multimesh(
				instance.multimesh, transforms, split["far"], group)
			_fill_multimesh(
				(nodes[type + "_near"] as MultiMeshInstance3D).multimesh,
				transforms, split["near"], group)
		else:
			_fill_multimesh(
				instance.multimesh, transforms,
				range(transforms.size()), group)
			if nodes.has(type + "_near"):
				# Вид пуст в этой раскладке — ближнее кольцо тоже пусто
				# (иначе в ноде остались бы прошлые буферы).
				(nodes[type + "_near"] as MultiMeshInstance3D) \
					.multimesh.instance_count = 0


## Разбивка раскладки вида на ближнее кольцо теней (≤ SHADOW_RING_M от
## center) и дальнюю часть — индексы в transforms (П17 п.13, ULTRA).
static func near_far_indices(transforms: Array, center: Vector2) -> Dictionary:
	var near: Array[int] = []
	var far: Array[int] = []
	for i: int in transforms.size():
		var xf: Transform3D = transforms[i]
		if Vector2(xf.origin.x, xf.origin.z).distance_to(center) \
				<= SHADOW_RING_M:
			near.append(i)
		else:
			far.append(i)
	return {"near": near, "far": far}


## Буфер одной ноды: трансформы/цвета исходной раскладки по индексам
## (near/far-наборы — подмножества одной раскладки вида).
static func _fill_multimesh(
		mm: MultiMesh,
		transforms: Array,
		indices: Array,
		group: Dictionary,
) -> void:
	mm.instance_count = indices.size()
	var colors: PackedColorArray = group.get("colors", PackedColorArray())
	for slot: int in indices.size():
		var i: int = indices[slot]
		mm.set_instance_transform(slot, transforms[i])
		if i < colors.size():
			mm.set_instance_color(slot, colors[i])
