# Генератор острова (раздел 6 SPEC, стиль low-poly): чистые данные без нод —
# карта высот 257 × 257 точек с шагом 1 м из FastNoiseLite с фиксированным
# seed и RandomNumberGenerator (детерминизм: повторный вызов даёт тот же
# результат; тест — на хеш высот и списка предметов). Суша 1–22 м, вокруг
# море с плавным спадом к берегу. Меш рельефа и коллизия (HeightMapShape3D)
# строит terrain.gd из той же карты; крутые перепады ≥ 0.9 м на метр —
# непроходимые стены, их прикрывают предметы-призмы (prop_meshes.gd):
# уступ получает чистую вертикальную стену, а не «лестницу» рельефа.
# Предметы раскладываются по правилам зон тем же seed; зоны, POI, монеты
# (ровно 60), точки мобов и камни духа сохраняют расположение кубической
# версии (П0–П4).
class_name IslandGen
extends RefCounted

const PAL: Palette = preload("res://assets/palette.tres")

## Seed генерации (фиксирован; смена меняет весь остров и хеш в тесте).
const SEED_VALUE: int = 20261002
## Половина размера карты в точках (x, z ∈ [−128, 128], 257 × 257).
const HALF: int = 128
const POINTS: int = HALF * 2 + 1
## Уровень воды (море и озеро), м.
const SEA_LEVEL: float = -0.15
## Дно моря у края карты, м.
const SEA_FLOOR: float = -6.0
## Порог «море» в данных высот: ниже — вода, выравнивание склонов не трогает.
const SEA_H: float = 0.3
## Радиусы маски острова: внутри — суша, дальше плавный спад в море.
const ISLAND_R_IN: float = 58.0
const ISLAND_R_OUT: float = 112.0
## Предел шага рельефа при выравнивании (м перепада на 1 м клетки): 0.9 < 45°
## — склон, по которому идёт персонаж; круче — стена.
const MAX_STEP: float = 0.9
## Высоты суши, м (раздел 6: 1–22 м).
const LAND_MIN: float = 1.0
const LAND_MAX: float = 22.0

## Высота террас: площадь и руины — плоские, руины чуть выше площади.
const PLAZA_H: float = 2.0
const RUINS_H: float = 3.0

## Каньон расщелины: прямоугольник точек и высоты дна/кромки.
const CREVASSE_X0: int = 26
const CREVASSE_X1: int = 98
const CREVASSE_Z0: int = 52
const CREVASSE_Z1: int = 62
const CREVASSE_FLOOR_H: float = 1.0
const CREVASSE_RIM_H: float = 6.0
## Кромка держит высоту 6 в полосе 2 м от края и плавно сливается с рельефом
## на протяжении 5 м — подход к расщелине пологий, стены каньона вертикальные.
const CREVASSE_RIM_BAND: float = 2.0
const CREVASSE_RIM_BLEND: float = 5.0

## Мостки через расщелину: две переправы, настил чуть выше кромки.
## Восточнее x ≈ 56 южный берег каньона уходит под море (каньон
## раскрывается в пролив) — обе переправы стоят в сухопутной части.
const BRIDGE_X: PackedInt32Array = [33, 52]
const BRIDGE_DECK_H: float = CREVASSE_RIM_H + 0.18

## Зоны (раздел 6): имя для --dev-spawn и F3, круг для названия места.
## Порядок — как в палитрах зон (Palette.zone_*).
const ZONES: Array[Dictionary] = [
	{"name": "plaza", "center": Vector2(0, 4), "radius": 20.0},
	{"name": "forest", "center": Vector2(-52, -52), "radius": 44.0},
	{"name": "ruins", "center": Vector2(58, -48), "radius": 30.0},
	{"name": "hills", "center": Vector2(-58, 42), "radius": 42.0},
	{"name": "crevasse", "center": Vector2(62, 57), "radius": 42.0},
	{"name": "lake", "center": Vector2(6, 82), "radius": 26.0},
]

## Смотровые площадки (раздел 9.3): площадка 3 × 3 точки на 3.0 м выше
## базиса — без подсадки не забраться, с подсадкой — можно.
const LOOKOUTS: Array[Vector2i] = [
	Vector2i(-72, 34),
	Vector2i(-52, 28),
	Vector2i(-66, 56),
	Vector2i(-44, 48),
]
const LOOKOUT_BASE_H: float = 7.0
const LOOKOUT_TOP_H: float = 10.0

## Типы предметов с коллизией (рецепт формы — в prop_meshes.gd).
## ruin_gate — только рама: проём закрывает узел RuinGate (П5, раздел 9.2).
const SOLID_TYPES: PackedStringArray = [
	"tree_leafy", "tree_spruce", "boulder", "rock_pillar", "rock_wall",
	"ruin_block", "ruin_tower", "ruin_arch", "ruin_column", "bench",
	"board", "beacon", "pier_post", "plank_deck", "boat",
]


## Полные данные острова (детерминированы): heights (карта высот, м),
## props (предметы: тип, позиция, поворот, масштаб, вариант, тон), tint
## (подсказки цвета рельефа), water, hang, stones, spawn_zones, beacons,
## coins (ровно 60), mobs, poi, bounds.
static func generate() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_VALUE
	var shape := _noise(SEED_VALUE, 1.0 / 90.0, 4)
	var detail := _noise(SEED_VALUE + 1, 1.0 / 28.0, 2)
	var heights := PackedFloat32Array()
	heights.resize(POINTS * POINTS)
	for z: int in range(-HALF, HALF + 1):
		for x: int in range(-HALF, HALF + 1):
			heights[_idx(x, z)] = _base_height(x, z, shape, detail)
	_apply_zones(heights)
	_limit_slopes(heights, {})
	_carve_crevasse(heights)
	_bridge_ramps(heights)
	_lookouts(heights)
	# Второй проход выравнивания: запланированные обрывы (каньон, площадки
	# смотровых) защищены, а их кромки получают пологий подход к рельефу.
	_limit_slopes(heights, _protected_cells())
	var data := {
		"heights": heights,
		"props": [],
		"tint": _tint_hints(),
		"water": {
			"sea": {"center": Vector2(0, 0), "size": Vector2(HALF * 2, HALF * 2), "level": SEA_LEVEL},
			"lake": {"center": Vector2(6, 82), "size": Vector2(30, 30), "level": SEA_LEVEL},
		},
	}
	var props: Array = data["props"]
	# Точки интереса резервируются до посадки деревьев: на их клетках ничего
	# не вырастает. Камни духа и спавны — на прежних местах кубической версии.
	var stones: Array[Vector3] = []
	var spawns: Dictionary = {}
	var reserved: Dictionary = _points_of_interest(heights, stones, spawns)
	var beacons: Array[Vector3] = _beacons(heights, props, reserved)
	_trees_and_rocks(heights, props, rng, reserved)
	_crevasse_walls(props, rng)
	_lookout_walls(props, rng)
	_lookout_trails(props, rng)
	_bridges(props, rng)
	var ruins: Dictionary = _ruins(heights, props, rng)
	var pier: Dictionary = _pier_and_boats(heights, props)
	var fire: Dictionary = _campfire_and_board(heights, props)
	var lookouts: Array = []
	for center: Vector2i in LOOKOUTS:
		lookouts.append({
			"center": Vector3(float(center.x), LOOKOUT_TOP_H, float(center.y)),
		})
	data["stones"] = stones
	data["spawn_zones"] = spawns
	data["beacons"] = beacons
	data["coins"] = _coins(heights, props, ruins, pier, rng)
	data["mobs"] = _mobs(heights, rng)
	data["hang"] = _hang()
	data["poi"] = {"ruins": ruins, "pier": pier, "campfire": fire, "lookouts": lookouts}
	data["bounds"] = HALF - 0.5
	props.sort_custom(_prop_less)
	return data


## Хеш данных острова (тест детерминизма: два вызова generate → хеши
## совпадают; также ловит незапланированное изменение генератора).
static func island_hash(data: Dictionary) -> int:
	var h: int = SEED_VALUE
	for height: float in (data["heights"] as PackedFloat32Array):
		h = hash([h, height])
	for prop: Dictionary in data["props"]:
		h = hash([
			h, String(prop["type"]), prop["pos"], prop["yaw"],
			prop["scale"], int(prop["variant"]), prop["tint"],
		])
	for coin: Vector3 in data["coins"]:
		h = hash([h, coin])
	for mob: Dictionary in data["mobs"]:
		h = hash([h, mob])
	return h


## Достижимость пешком (тесты «все зоны достижимы», «смотровые — нет»):
#  заливка от спавна площади по верхним поверхностям, перепад ≤ MAX_STEP
#  на метр (склон ≤ 45° — как floor_max_angle персонажа). Вода не проходима
#  — проверяется сухопутная связность; подсадка на голову требует второго
#  игрока и в заливку не входит. Проходимые постройки (мостки, пирс, плоты)
#  добавляют свою поверхность.
static func walkable_reach(data: Dictionary, terrain_only: bool = false) -> Dictionary:
	var heights := _surface_heights(data, terrain_only)
	var start := Vector2i(0, 10)  # спавн площади
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [start]
	visited[start] = true
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		var h0: float = heights[current]
		for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = current + dir
			if visited.has(next) or not heights.has(next):
				continue
			if heights[next] - h0 <= MAX_STEP + 0.01:
				visited[next] = true
				queue.append(next)
	return visited


## Высота рельефа в точке (м) или NaN за краем карты.
static func top_of(data: Dictionary, x: int, z: int) -> float:
	if absi(x) > HALF or absi(z) > HALF:
		return NAN
	return (data["heights"] as PackedFloat32Array)[_idx(x, z)]


## Взвешенный цвет палитры зон в точке: зоны смешиваются по весам
## 1 − d/(r·1.4) (радиус влияния чуть шире круга названия зоны, чтобы
## границы были плавными). Общий смеситель для рельефа и предметов.
static func zone_blend(pos: Vector2, colors: PackedColorArray) -> Color:
	var mix := Color(0.0, 0.0, 0.0)
	var total: float = 0.0
	for i: int in ZONES.size():
		var zone: Dictionary = ZONES[i]
		var reach: float = float(zone["radius"]) * 1.4
		var d: float = pos.distance_to(zone["center"])
		if d >= reach:
			continue
		var weight: float = 1.0 - d / reach
		mix += colors[i] * weight
		total += weight
	if total <= 0.0:
		return Color.WHITE
	return mix / total


## Индекс точки в карте высот.
static func _idx(x: int, z: int) -> int:
	return (z + HALF) * POINTS + (x + HALF)


## Стабильный порядок предметов (хеш и сборка сцены не зависят от порядка
#  обхода словарей): по типу, затем по позиции.
static func _prop_less(a: Dictionary, b: Dictionary) -> bool:
	var type_a := String(a["type"])
	var type_b := String(b["type"])
	if type_a != type_b:
		return type_a < type_b
	var pa: Vector3 = a["pos"]
	var pb: Vector3 = b["pos"]
	if !is_equal_approx(pa.x, pb.x):
		return pa.x < pb.x
	if !is_equal_approx(pa.z, pb.z):
		return pa.z < pb.z
	return pa.y < pb.y


# --- Базовый рельеф ---

static func _noise(seed_value: int, frequency: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	return noise


## Шум + круговая маска → базовая высота (до зон). land_t < 0.17 — море с
## плавным углублением к краю карты, у кромки суши — песчаный пляж.
static func _base_height(
	x: int, z: int, shape: FastNoiseLite, detail: FastNoiseLite
) -> float:
	var e: float = shape.get_noise_2d(x, z) * 0.7 + detail.get_noise_2d(x, z) * 0.3
	var r := Vector2(x, z).length()
	var mask: float = 1.0 - smoothstep(ISLAND_R_IN, ISLAND_R_OUT, r)
	var land_t: float = (e * 0.5 + 0.5) * mask
	if land_t < 0.17:
		# Море: от кромки (чуть ниже воды) до дна у края карты.
		return lerpf(SEA_H, SEA_FLOOR, pow(1.0 - land_t / 0.17, 1.2))
	# Степень > 1 держит широкие пляжи и пологий берег у кромки суши.
	var t: float = (land_t - 0.17) / 0.83
	return lerpf(LAND_MIN, LAND_MAX, pow(t, 1.25))


## Зоны меняют высоты: площадь и руины — плоские террасы (там всегда суша),
## холмы усилены к центру (не выше LAND_MAX), лес пологий, озеро вырезано
## с пляжем. Расщелина и смотровые прорезаются после выравнивания склонов —
## их обрывы запланированы, весь остальной остров проходим пешком.
static func _apply_zones(heights: PackedFloat32Array) -> void:
	for z: int in range(-HALF, HALF + 1):
		for x: int in range(-HALF, HALF + 1):
			var h: float = heights[_idx(x, z)]
			var is_land: bool = h > SEA_H
			# Холмы: усиление высоты к центру зоны (до +13 м).
			var d_hills: float = Vector2(x + 58.0, z - 42.0).length()
			if is_land and d_hills < 42.0:
				var boost: float = 1.0 - d_hills / 42.0
				h = minf(h + boost * boost * 13.0, LAND_MAX)
			# Лес: пологий, без обрывов.
			if is_land and Vector2(x + 52.0, z + 52.0).length() < 40.0:
				h = clampf(h, 2.0, 6.0)
			# Площадь: плоская терраса (запланированная суша в центре острова).
			if Vector2(x, z - 4.0).length() < 18.0:
				h = PLAZA_H
			# Руины: ровная терраса под стенами (вытянута к площади).
			if Vector2(x - 58.0, z + 48.0).length() < 24.0:
				h = RUINS_H
			# Озеро: котловина с водой и песчаной кромкой.
			var d_lake: float = Vector2(x - 6.0, z - 82.0).length()
			if d_lake < 16.0:
				h = -1.2
			elif is_land and d_lake < 21.0:
				h = minf(h, 0.9)
			heights[_idx(x, z)] = h


## Выровнять склоны: после зон соседние точки могут отличаться больше чем
## на MAX_STEP — такие «стены» ломают проходимость. Проход капает высоту до
## «минимальный сосед-суша + MAX_STEP», пока рельеф не станет лестницей
## с шагом ≤ MAX_STEP (морские соседи не считаются — береговой обрыв
## остаётся). Клетки из protected (дно и кромка каньона, площадки смотровых)
## не понижаются: запланированные обрывы.
static func _limit_slopes(heights: PackedFloat32Array, protected: Dictionary) -> void:
	var changed := true
	var iteration := 0
	while changed and iteration < 24:
		changed = false
		iteration += 1
		var reverse: bool = iteration % 2 == 0
		for index: int in range(POINTS * POINTS):
			var i: int = heights.size() - 1 - index if reverse else index
			var x: int = (i % POINTS) - HALF
			var z: int = (i / POINTS) - HALF
			var cell := Vector2i(x, z)
			if protected.has(cell):
				continue
			var h: float = heights[i]
			if h <= SEA_H:
				continue
			var min_neighbor: float = 1e9
			for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + dir.x
				var nz: int = z + dir.y
				if absi(nx) > HALF or absi(nz) > HALF:
					continue
				var nh: float = heights[_idx(nx, nz)]
				if nh > SEA_H:
					min_neighbor = minf(min_neighbor, nh)
			if min_neighbor < 1e9 and h > min_neighbor + MAX_STEP:
				heights[i] = min_neighbor + MAX_STEP
				changed = true


## Клетки с запланированными обрывами: каньон и его кромка, площадки
## смотровых (кольцо стены включительно — перепад ровно 3 м сохраняется).
static func _protected_cells() -> Dictionary:
	var cells: Dictionary = {}
	for x: int in range(CREVASSE_X0 - 3, CREVASSE_X1 + 4):
		for z: int in range(CREVASSE_Z0 - 3, CREVASSE_Z1 + 4):
			if _dist_to_crevasse(x, z) <= CREVASSE_RIM_BAND:
				cells[Vector2i(x, z)] = true
	for center: Vector2i in LOOKOUTS:
		for dx: int in range(-2, 3):
			for dz: int in range(-2, 3):
				cells[center + Vector2i(dx, dz)] = true
	return cells


## Расщелина: дно каньона и приподнятая кромка, плавно сливающаяся
## с рельефом. Прорезается после выравнивания — стены каньона вертикальные
## (перепад 5 м на клетку), переправа только по мосткам.
static func _carve_crevasse(heights: PackedFloat32Array) -> void:
	for z: int in range(-HALF, HALF + 1):
		for x: int in range(-HALF, HALF + 1):
			var in_canyon: bool = x >= CREVASSE_X0 and x <= CREVASSE_X1 \
				and z >= CREVASSE_Z0 and z <= CREVASSE_Z1
			if in_canyon:
				heights[_idx(x, z)] = CREVASSE_FLOOR_H
				continue
			var h: float = heights[_idx(x, z)]
			if h <= SEA_H:
				continue
			var d: float = _dist_to_crevasse(x, z)
			if d <= CREVASSE_RIM_BAND:
				heights[_idx(x, z)] = CREVASSE_RIM_H
			elif d <= CREVASSE_RIM_BAND + CREVASSE_RIM_BLEND:
				var t: float = (d - CREVASSE_RIM_BAND) / CREVASSE_RIM_BLEND
				heights[_idx(x, z)] = lerpf(CREVASSE_RIM_H, h, t)


## Смотровые: базис-поляна 7 м, площадка 3 × 3 точки на 10 м — уступ ровно
## 3.0 м. Подход к базису выравнивает второй проход _limit_slopes.
static func _lookouts(heights: PackedFloat32Array) -> void:
	for center: Vector2i in LOOKOUTS:
		for dx: int in range(-7, 8):
			for dz: int in range(-7, 8):
				var x: int = center.x + dx
				var z: int = center.y + dz
				if absi(x) > HALF or absi(z) > HALF:
					continue
				var platform: bool = absi(dx) <= 1 and absi(dz) <= 1
				heights[_idx(x, z)] = LOOKOUT_TOP_H if platform else LOOKOUT_BASE_H


static func _dist_to_crevasse(x: int, z: int) -> float:
	var dx: float = maxf(maxf(CREVASSE_X0 - x, 0.0), x - CREVASSE_X1)
	var dz: float = maxf(maxf(CREVASSE_Z0 - z, 0.0), z - CREVASSE_Z1)
	return Vector2(dx, dz).length()


## Пологие подходы к мостам: полоса рельефа шириной в настил поднимается
## к кромке рампой с шагом MAX_STEP (естественный рельеф у переправ бывает
## заметно ниже кромки — без рампы вход на мост превращается в стену).
## Клетки только поднимаются (maxf), ничего не срезается.
static func _bridge_ramps(heights: PackedFloat32Array) -> void:
	for bx: int in BRIDGE_X:
		for side: int in [0, 1]:
			# Север: кромка на z ∈ {Z0-2, Z0-1}, рампа уходит дальше на север;
			# юг: кромка на z ∈ {Z1+1, Z1+2}, рампа — дальше на юг.
			var z_rim: int = CREVASSE_Z0 - 2 if side == 0 else CREVASSE_Z1 + 2
			var step: int = -1 if side == 0 else 1
			for k: int in range(1, 11):
				var target: float = CREVASSE_RIM_H - MAX_STEP * float(k)
				var z: int = z_rim + step * k
				var done: bool = true
				for x: int in range(bx - 1, bx + 2):
					if absi(x) > HALF or absi(z) > HALF:
						continue
					var i: int = _idx(x, z)
					if heights[i] > SEA_H:
						heights[i] = maxf(heights[i], target)
						done = false
				if done or target <= LAND_MIN:
					break


## Подсказки цвета рельефа (terrain.gd): террасы и площадки — камень своей
## зоны вместо материала по высоте/склону; вне подсказок цвет смешивается
## из базовых материалов и зональных тонов по радиусам зон.
static func _tint_hints() -> Dictionary:
	var tint: Dictionary = {}
	# Площадь: вымощенная терраса — тёплый камень зоны (охра/терракота).
	for x: int in range(-19, 20):
		for z: int in range(-15, 24):
			if Vector2(x, z - 4.0).length() < 18.0:
				tint[Vector2i(x, z)] = {"zone": 0}
	# Руины: терраса — серо-голубой камень зоны с мхом.
	for x: int in range(33, 84):
		for z: int in range(-73, -22):
			if Vector2(x - 58.0, z + 48.0).length() < 24.0:
				tint[Vector2i(x, z)] = {"zone": 2}
	# Расщелина: дно каньона — холодный камень зоны.
	for x: int in range(CREVASSE_X0, CREVASSE_X1 + 1):
		for z: int in range(CREVASSE_Z0, CREVASSE_Z1 + 1):
			tint[Vector2i(x, z)] = {"zone": 4}
	# Смотровые: площадки — бежевый камень зоны холмов.
	for center: Vector2i in LOOKOUTS:
		for dx: int in range(-1, 2):
			for dz: int in range(-1, 2):
				tint[center + Vector2i(dx, dz)] = {"zone": 3}
	return tint


# --- Точки интереса (те же клетки, что в кубической версии) ---

## Камни духа (по одному на зону) и точки появления --dev-spawn. Возвращает
## множество зарезервированных клеток (по ним не растут деревья и не ставятся
## декорации), чтобы точка интереса не оказалась внутри ствола.
static func _points_of_interest(
	heights: PackedFloat32Array, stones: Array[Vector3], spawns: Dictionary
) -> Dictionary:
	var reserved: Dictionary = {}
	var stone_cells: Array[Vector2i] = [
		Vector2i(0, 12), Vector2i(-52, -38), Vector2i(58, -32),
		Vector2i(-46, 32), Vector2i(40, 46), Vector2i(4, 66),
	]
	for cell: Vector2i in stone_cells:
		_ensure_land(heights, cell, 1.2)
		reserved[cell] = true
		stones.append(Vector3(cell.x + 0.5, heights[_idx(cell.x, cell.y)], cell.y + 0.5))
	var spawn_cells: Dictionary = {
		"plaza": Vector2i(0, 10),
		"forest": Vector2i(-52, -40),
		"ruins": Vector2i(58, -30),
		"hills": Vector2i(-46, 32),
		"crevasse": Vector2i(41, 46),
		"lake": Vector2i(4, 64),
	}
	for zone: String in spawn_cells:
		var cell: Vector2i = spawn_cells[zone]
		_ensure_land(heights, cell, 1.2)
		reserved[cell] = true
		spawns[zone] = Vector3(cell.x + 0.5, heights[_idx(cell.x, cell.y)] + 0.1, cell.y + 0.5)
	return reserved


## Поднять точку до минимальной высоты, если попала в воду/пляж: участок
## 5 × 5 с затуханием, чтобы не появилось непроходимой ступеньки.
static func _ensure_land(heights: PackedFloat32Array, cell: Vector2i, min_h: float) -> void:
	var h0: float = heights[_idx(cell.x, cell.y)]
	if h0 >= min_h:
		return
	for dx: int in range(-2, 3):
		for dz: int in range(-2, 3):
			var x: int = cell.x + dx
			var z: int = cell.y + dz
			if absi(x) > HALF or absi(z) > HALF:
				continue
			var fall: float = 1.0 - (absi(dx) + absi(dz)) / 5.0
			var target: float = lerpf(h0, min_h, fall)
			var i: int = _idx(x, z)
			heights[i] = maxf(heights[i], target)


## Пять маяков (раздел 7): по одному у зон; зажигание — П5, здесь башни
## (предмет «beacon», лампа в башне тёмная — луч появится на П5).
static func _beacons(
	heights: PackedFloat32Array, props: Array, reserved: Dictionary
) -> Array[Vector3]:
	var cells: Array[Vector2i] = [
		Vector2i(-60, -40), Vector2i(42, -48), Vector2i(-58, 22),
		Vector2i(62, 44), Vector2i(-14, 76),
	]
	var rng := rng_static()
	var beacons: Array[Vector3] = []
	for cell: Vector2i in cells:
		_ensure_land(heights, cell, 1.5)
		for dx: int in range(-1, 2):
			for dz: int in range(-1, 2):
				reserved[cell + Vector2i(dx, dz)] = true
		var pos := Vector3(cell.x + 0.5, heights[_idx(cell.x, cell.y)], cell.y + 0.5)
		beacons.append(pos)
		_add_prop(props, rng, &"beacon", pos, rng.randf_range(-0.1, 0.1),
			Vector3.ONE * rng.randf_range(0.95, 1.05), "stone", 1)
	return beacons


# --- Деревья, камни, трава, цветы ---

## Предметы по правилам зон (раздел 6): плотность, отступы от POI и троп.
## Позиции и масштабы берёт из rng — детерминированно при фиксированном seed.
static func _trees_and_rocks(
	heights: PackedFloat32Array, props: Array, rng: RandomNumberGenerator,
	reserved: Dictionary,
) -> void:
	var forest := Vector2(-52.0, -52.0)
	var trees: Dictionary = {}
	for z: int in range(-HALF, HALF + 1):
		for x: int in range(-HALF, HALF + 1):
			var cell := Vector2i(x, z)
			if reserved.has(cell):
				continue
			var h: float = heights[_idx(x, z)]
			if h <= 0.6 or h > 18.5:
				continue
			var grassy: bool = h > 0.9 and h < 16.0
			var d_forest: float = Vector2(x, z).distance_to(forest)
			var in_hills: bool = Vector2(x + 58.0, z - 42.0).length() < 42.0
			# Лес: деревья с отступом 2 м, ели вперемежку (примерно каждая
			# пятая). Лиственных — 5 CC0-вариантов (шаг 3 П4.5: лес гуще).
			if d_forest < 40.0 and grassy:
				if rng.randf() < 0.07 and _no_trees_near(trees, x, z, 2):
					trees[cell] = true
					var spruce: bool = rng.randf() < 0.22
					_prop(props, rng, cell, h,
						"tree_spruce" if spruce else "tree_leafy", "leaf",
						3 if spruce else 5)
				elif rng.randf() < 0.022:
					_prop(props, rng, cell, h, "bush", "leaf")
			# Редкие деревья вокруг леса (не на площади).
			elif d_forest < 56.0 and Vector2(x, z - 4.0).length() > 20.0 and grassy:
				if rng.randf() < 0.01 and _no_trees_near(trees, x, z, 3):
					trees[cell] = true
					var spruce: bool = rng.randf() < 0.3
					_prop(props, rng, cell, h,
						"tree_spruce" if spruce else "tree_leafy", "leaf")
			# Холмы: валуны повыше, редкие ели, камни у вершин.
			elif in_hills and h > 4.0:
				if rng.randf() < 0.012:
					_prop(props, rng, cell, h, "boulder", "stone")
				elif h < 13.0 and rng.randf() < 0.006:
					_prop(props, rng, cell, h, "tree_spruce", "leaf")
				elif h > 16.0 and rng.randf() < 0.02:
					_prop(props, rng, cell, h, "rock_pillar", "stone")
			# Пляж: камешки.
			elif h <= 0.9 and h > -0.2 and rng.randf() < 0.05:
				_prop(props, rng, cell, h, "pebble", "stone")
	# Трава и цветы на лугах (MultiMesh, раздел 16: трава исчезает дальше 40 м).
	for z: int in range(-HALF, HALF + 1):
		for x: int in range(-HALF, HALF + 1):
			var cell := Vector2i(x, z)
			if reserved.has(cell) or trees.has(cell):
				continue
			var h: float = heights[_idx(x, z)]
			if h <= 0.9 or h > 15.0:
				continue
			if Vector2(x, z - 4.0).length() < 18.0:
				continue  # площадь — вымощенная, без травы
			if Vector2(x - 58.0, z + 48.0).length() < 25.0:
				continue  # терраса руин — камень
			if rng.randf() < 0.13:
				_prop(props, rng, cell, h, "grass_tuft", "grass")
			elif rng.randf() < 0.025:
				_prop(props, rng, cell, h, "flower", "flower")
	# Камыши по кромке озера (шаг 3 П4.5): полоса берега шириной ~0.5 м
	# над уровнем воды; камыш проходим, виден с 40 м как трава.
	for z: int in range(-HALF, HALF + 1):
		for x: int in range(-HALF, HALF + 1):
			var cell := Vector2i(x, z)
			if reserved.has(cell):
				continue
			var h: float = heights[_idx(x, z)]
			if h <= SEA_LEVEL or h > SEA_LEVEL + 0.55:
				continue
			if Vector2(x - 6.0, z - 82.0).length() > 18.0:
				continue
			if rng.randf() < 0.3:
				_prop(props, rng, cell, h, "reed", "grass", 2)
	# Немного цветов по кромке площади (шаг 3 П4.5): кольцо радиуса 13–16 м,
	# не задевающее костёр (4.5 м), лавки и вымощенный центр.
	for i: int in 10:
		var angle: float = TAU * i / 10.0 + rng.randf_range(-0.15, 0.15)
		var ring := Vector2(0, 4) + Vector2(cos(angle), sin(angle)) \
			* rng.randf_range(13.0, 16.5)
		var cell := Vector2i(roundi(ring.x), roundi(ring.y))
		if reserved.has(cell):
			continue
		_prop(props, rng, cell, PLAZA_H, "flower", "flower")


static func _no_trees_near(trees: Dictionary, x: int, z: int, radius: int) -> bool:
	for dx: int in range(-radius, radius + 1):
		for dz: int in range(-radius, radius + 1):
			if trees.has(Vector2i(x + dx, z + dz)):
				return false
	return true


## Добавить предмет «по клетке»: позиция у точки сетки с лёгким сдвигом,
## случайный поворот и разброс масштаба. Типы с.kind-оттенком получают тон
## зоны (instance-цвет MultiMesh смешивается с вершинными цветами меша).
static func _prop(
	props: Array, rng: RandomNumberGenerator, cell: Vector2i, h: float,
	type: String, kind: String, variants: int = 3,
) -> void:
	var scale: float = rng.randf_range(0.85, 1.25)
	var pos := Vector3(
		cell.x + rng.randf_range(-0.3, 0.3), h, cell.y + rng.randf_range(-0.3, 0.3)
	)
	_add_prop(props, rng, StringName(type), pos, rng.randf_range(0.0, TAU),
		Vector3(scale, scale * rng.randf_range(0.9, 1.15), scale), kind, variants)


## Добавить предмет с явной геометрией (стены, постройки, мостки).
static func _add_prop(
	props: Array, rng: RandomNumberGenerator, type: StringName,
	pos: Vector3, yaw: float, scale: Vector3, kind: String,
	variants: int = 3,
) -> void:
	props.append({
		"type": type,
		"pos": pos,
		"yaw": yaw,
		"scale": scale,
		"variant": rng.randi_range(0, maxi(0, variants - 1)),
		"tint": _zone_tint(rng, Vector2(pos.x, pos.z), kind),
	})


## Тон предмета: лёгкая вариация яркости + уклон к палитре зоны в этой
## точке (zone_blend). kind: leaf — листва/кусты (zone_leaf), stone — камни
## и стены (zone_stone), grass — трава (zone_ground), flower — цветок из
## палитры, plain — без уклона. Уклон умеренный: стволы и камни не
## перекрашиваются целиком.
static func _zone_tint(rng: RandomNumberGenerator, pos: Vector2, kind: String) -> Color:
	var tint := Color.WHITE * rng.randf_range(0.92, 1.08)
	tint.a = 1.0
	match kind:
		"flower":
			var flowers: PackedColorArray = PAL.flowers
			return flowers[rng.randi_range(0, flowers.size() - 1)].lerp(Color.WHITE, 0.15)
		"plain":
			return tint
	var zone_color := Color.WHITE
	if kind == "stone":
		zone_color = zone_blend(pos, PAL.zone_stone)
	elif kind == "grass":
		zone_color = zone_blend(pos, PAL.zone_ground)
	else:
		zone_color = zone_blend(pos, PAL.zone_leaf)
	return tint.lerp(zone_color.lerp(Color.WHITE, 0.5), 0.5)


# --- Стены расщелины и смотровых (раздел 6: уступы — предметы) ---

## Скальные стены вдоль бортов каньона: призмы от дна до кромки прикрывают
## крутой перепад высот — чистая вертикальная стена вместо «лестницы».
static func _crevasse_walls(props: Array, rng: RandomNumberGenerator) -> void:
	var wall_h: float = CREVASSE_RIM_H - CREVASSE_FLOOR_H + 0.4
	var depth: float = 1.6
	# Северный и южный борта (перепад — в полосе точек каньона и кромки).
	for z: int in [CREVASSE_Z0, CREVASSE_Z1 + 1]:
		var x: float = CREVASSE_X0 - 0.5
		while x < CREVASSE_X1 + 0.5:
			var length: float = minf(rng.randf_range(2.5, 4.0), CREVASSE_X1 + 0.5 - x)
			_add_prop(props, rng, &"rock_wall",
				Vector3(x + length * 0.5, CREVASSE_FLOOR_H - 0.3, float(z)),
				rng.randf_range(-0.05, 0.05),
				Vector3(length, wall_h * rng.randf_range(0.97, 1.08), depth),
				"stone", 4)
			x += length + 0.15
	# Торцы каньона (запад и восток).
	for x0: int in [CREVASSE_X0 - 1, CREVASSE_X1 + 1]:
		var z: float = CREVASSE_Z0 - 0.5
		while z < CREVASSE_Z1 + 0.5:
			var length: float = minf(rng.randf_range(2.5, 4.0), CREVASSE_Z1 + 0.5 - z)
			_add_prop(props, rng, &"rock_wall",
				Vector3(float(x0), CREVASSE_FLOOR_H - 0.3, z + length * 0.5),
				PI / 2.0 + rng.randf_range(-0.05, 0.05),
				Vector3(length, wall_h * rng.randf_range(0.97, 1.08), depth),
				"stone", 4)
			z += length + 0.15
	# Камешки на дне.
	for i: int in range(24):
		var x: int = rng.randi_range(CREVASSE_X0 + 2, CREVASSE_X1 - 2)
		var z: int = rng.randi_range(CREVASSE_Z0 + 2, CREVASSE_Z1 - 2)
		_prop(props, rng, Vector2i(x, z), CREVASSE_FLOOR_H, "pebble", "stone")


## Кольцо скальных призм вокруг каждой смотровой площадки (уступ 3 м):
## грань рельефа проходит на 1.5 м от центра площадки 2 × 2 м. Север открыт —
## туда входит обходная тропа (раздел 9.3, запасной путь одиночки).
static func _lookout_walls(props: Array, rng: RandomNumberGenerator) -> void:
	var wall_h: float = LOOKOUT_TOP_H - LOOKOUT_BASE_H + 0.4
	for center: Vector2i in LOOKOUTS:
		for side: int in range(4):
			if side == 2:
				continue  # северная стена — разрыв под тропу
			var along_x: bool = side % 2 == 0
			var sign: float = 1.0 if side < 2 else -1.0
			var pos := Vector3(
				float(center.x) + (0.0 if along_x else sign * 1.5),
				LOOKOUT_BASE_H - 0.3,
				float(center.y) + (sign * 1.5 if along_x else 0.0),
			)
			_add_prop(props, rng, &"rock_wall", pos,
				(rng.randf_range(-0.04, 0.04) if along_x else PI / 2.0 + rng.randf_range(-0.04, 0.04)),
				Vector3(2.7, wall_h * rng.randf_range(0.97, 1.06), 0.9),
				"stone", 4)
		# Камешки на площадке.
		for i: int in range(3):
			_prop(props, rng, center + Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1)),
				LOOKOUT_TOP_H, "pebble", "stone")


## Обходная тропа на смотровую (раздел 9.3, запасной путь одиночки):
## дуга деревянных ступеней вокруг скалы — с юга через восток к северному
## разрыву стены. Каждая ступень выше предыдущей меньше автоподъёма —
## тропа проходима без чужой помощи, но дольше, чем подсадка или лестница.
static func _lookout_trails(props: Array, rng: RandomNumberGenerator) -> void:
	var steps: int = 10
	var radius: float = 2.9
	for center: Vector2i in LOOKOUTS:
		for i: int in steps:
			var t: float = float(i) / float(steps - 1)
			var angle: float = PI / 2.0 - t * PI
			var pos := Vector3(
				float(center.x) + radius * cos(angle),
				7.05 + t * 2.7,
				float(center.y) + radius * sin(angle),
			)
			# Ступень длинной стороной вдоль касательной дуги.
			_add_prop(props, rng, &"plank_deck", pos,
				atan2(sin(angle), -cos(angle)) + rng.randf_range(-0.03, 0.03),
				Vector3(1.5, 0.12, 1.2), "plain", 1)
		# Финальная ступень у северного разрыва — вход на площадку.
		_add_prop(props, rng, &"plank_deck",
			Vector3(float(center.x), 9.88, float(center.y) - 1.8), 0.0,
			Vector3(1.5, 0.12, 1.6), "plain", 1)


## Мостки: две переправы из досок на кромке (walk — поверхность BFS) и
## эстакадные опоры со дна каньона до настила — мост выглядит настоящим,
## а опоры под настилом не мешают ходить.
static func _bridges(props: Array, rng: RandomNumberGenerator) -> void:
	var deck_bottom: float = BRIDGE_DECK_H - 0.11
	for bx: int in BRIDGE_X:
		var z: int = CREVASSE_Z0 - 2
		while z <= CREVASSE_Z1 + 2:
			var length: float = minf(2.0, CREVASSE_Z1 + 3 - z)
			_add_prop(props, rng, &"plank_deck",
				Vector3(bx + rng.randf_range(0.4, 0.6), deck_bottom,
					z + length * 0.5),
				rng.randf_range(-0.03, 0.03),
				Vector3(1.7, 0.12, length), "plain", 1)
			z += int(length)
		# Опоры-эстакады: две стойки со дна каньона до настила.
		for post_z: int in [CREVASSE_Z0 + 1, CREVASSE_Z1 - 1]:
			_add_prop(props, rng, &"pier_post",
				Vector3(bx + 0.5, CREVASSE_FLOOR_H, float(post_z)),
				0.0, Vector3(1.15, deck_bottom - CREVASSE_FLOOR_H, 1.15),
				"plain", 1)


# --- Руины, пирс, костёр (геометрия та же, модель — из предметов) ---

## Руины: прямоугольник стен с проломами, ворота с башнями (проём закрыт
## тёмной плитой — откроется на П5), перед воротами три плиты, за воротами
## сундук; внутри обломки колонн. Терраса руин — RUINS_H.
static func _ruins(
	heights: PackedFloat32Array, props: Array, rng: RandomNumberGenerator
) -> Dictionary:
	var x0: int = 46
	var x1: int = 70
	var z0: int = -58
	var z1: int = -38
	for x: int in range(x0, x1 + 1):
		for z: int in range(z0, z1 + 1):
			var on_wall: bool = x == x0 or x == x1 or z == z0 or z == z1
			if not on_wall:
				continue
			# Ворота на стороне площади: проём x 57..58 закрыт тёмной плитой.
			if z == z1 and x >= 57 and x <= 58:
				_add_prop(props, rng, &"ruin_gate",
					Vector3(x + 0.5, RUINS_H, z + 0.5), 0.0, Vector3.ONE,
					"plain", 1)
				continue
			var height: float = rng.randf_range(1.6, 2.6)
			if rng.randf() < 0.3:
				height = 0.0  # пролом в стене
			if height > 0.0:
				_add_prop(props, rng, &"ruin_block",
					Vector3(x + 0.5, RUINS_H, z + 0.5), rng.randf_range(-0.05, 0.05),
					Vector3(1.0, height, 1.0), "plain")
	# Башни по сторонам ворот.
	for tower_x: int in [55, 60]:
		_add_prop(props, rng, &"ruin_tower",
			Vector3(tower_x + 0.5, RUINS_H, z1 + 0.5), 0.0, Vector3.ONE,
			"plain", 1)
	# Обломки колонн внутри.
	for i: int in range(6):
		var rx: int = rng.randi_range(x0 + 3, x1 - 3)
		var rz: int = rng.randi_range(z0 + 3, z1 - 3)
		_add_prop(props, rng, &"ruin_column",
			Vector3(rx + 0.5, RUINS_H, rz + 0.5), rng.randf_range(0.0, TAU),
			Vector3.ONE * rng.randf_range(0.8, 1.2), "plain", 1)
	# Две арки во дворе (шаг 3 П4.5, CC0 castle-kit): не на линии ворот —
	# проход к сундуку остаётся свободным.
	for arch: Vector2i in [Vector2i(51, -45), Vector2i(65, -53)]:
		_add_prop(props, rng, &"ruin_arch",
			Vector3(arch.x, RUINS_H, arch.y), rng.randf_range(0.0, TAU),
			Vector3.ONE, "plain", 1)
	return {
		"center": Vector3(58, RUINS_H, -48),
		"gate_center": Vector3(58, RUINS_H, float(z1)),
		"chest": Vector3(58, RUINS_H, -50),
		"plates": [
			Vector3(54, RUINS_H, z1 - 3),
			Vector3(58, RUINS_H, z1 - 3),
			Vector3(62, RUINS_H, z1 - 3),
		],
		"inside_rect": Rect2(Vector2(x0 + 1, z0 + 1), Vector2(x1 - x0 - 1, z1 - z0 - 1)),
	}


## Пирс в озеро (настил на 0.5 м над водой, сваи со дна) и две лодочки-плоты.
static func _pier_and_boats(heights: PackedFloat32Array, props: Array) -> Dictionary:
	var rng := rng_static()
	var deck_h: float = 1.0
	for x: int in [5, 6]:
		var z: int = 61
		while z <= 72:
			var length: float = minf(2.0, 73 - z)
			_add_prop(props, rng, &"plank_deck",
				Vector3(x + 0.5, deck_h - 0.12, z + length * 0.5), 0.0,
				Vector3(0.95, 0.12, length), "plain", 1)
			# Свая от дна до низа настила (на сухом берегу не ставится).
			if z % 3 == 0:
				var ground: float = heights[_idx(x, z)]
				if ground < deck_h - 0.2:
					_add_prop(props, rng, &"pier_post",
						Vector3(x + 0.5, ground, float(z)), 0.0,
						Vector3(1.0, deck_h - 0.12 - ground, 1.0), "plain", 1)
			z += int(length)
	for boat: Vector2i in [Vector2i(13, 74), Vector2i(-3, 78)]:
		_add_prop(props, rng, &"boat",
			Vector3(boat.x + 1.0, SEA_LEVEL + 0.05, boat.y + 1.0),
			TAU * (0.125 if boat.x > 0 else 0.625), Vector3.ONE, "plain", 1)
	return {
		"deck_end": Vector3(6.0, deck_h + 0.1, 71.5),
		"boats": [Vector3(14.0, SEA_LEVEL + 0.4, 74.5), Vector3(-2.0, SEA_LEVEL + 0.4, 78.5)],
	}


## Костёр на площади: каменное кольцо, лавки вокруг, доска события севернее.
## Сидение и огонь-логика — П5; здесь геометрия и позиции (площадь — PLAZA_H).
static func _campfire_and_board(heights: PackedFloat32Array, props: Array) -> Dictionary:
	var fire := Vector2i(0, 2)
	var ring_rng := rng_static()
	for i: int in range(8):
		var angle: float = TAU * i / 8.0
		var ring := Vector2(fire) + Vector2(cos(angle), sin(angle)) * 1.5
		_add_prop(props, ring_rng, &"boulder",
			Vector3(ring.x, PLAZA_H - 0.15, ring.y), angle,
			Vector3(0.5, 0.42, 0.5), "stone")
	var benches: Array[Vector3] = []
	for i: int in range(8):
		var angle: float = TAU * i / 8.0 + PI / 8.0
		var bench := Vector2(fire) + Vector2(cos(angle), sin(angle)) * 4.5
		# Лавка лицом к костру (модель смотрит в +Z).
		var yaw: float = atan2(-cos(angle), -sin(angle))
		_add_prop(props, ring_rng, &"bench",
			Vector3(bench.x, PLAZA_H, bench.y), yaw, Vector3.ONE, "plain", 1)
		benches.append(Vector3(bench.x, PLAZA_H + 0.45, bench.y))
	_add_prop(props, ring_rng, &"board",
		Vector3(0.5, PLAZA_H, -5.5), 0.0, Vector3.ONE, "plain", 1)
	return {
		"center": Vector3(0.5, PLAZA_H, 2.5),
		"benches": benches,
		"board": Vector3(0.5, PLAZA_H + 1.0, -5.5),
	}


## Детерминированный ГПСЧ для «строительных» предметов без внешнего rng
## (пирс, костёр): свой поток чисел, чтобы правки леса не двигали пирс.
static func rng_static() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_VALUE + 17
	return rng


# --- Монеты (ровно 60, раздел 8) ---

static func _coins(
	heights: PackedFloat32Array, props: Array, ruins: Dictionary, pier: Dictionary,
	rng: RandomNumberGenerator,
) -> Array[Vector3]:
	var coins: Array[Vector3] = []
	# Смотровые: по 4 на площадке 2 × 2 м (верх LOOKOUT_TOP_H).
	for center: Vector2i in LOOKOUTS:
		for offset: Vector2 in [
			Vector2(0.65, 0.0), Vector2(-0.65, 0.0),
			Vector2(0.0, 0.65), Vector2(0.0, -0.65),
		]:
			coins.append(Vector3(
				float(center.x) + offset.x, LOOKOUT_TOP_H + 0.35,
				float(center.y) + offset.y
			))
	# Мостки: по 6 вдоль каждой переправы (настил BRIDGE_DECK_H).
	for bx: int in BRIDGE_X:
		for i: int in range(6):
			var z: int = CREVASSE_Z0 - 1 + i * 2
			coins.append(Vector3(bx + 0.5, BRIDGE_DECK_H + 0.3, z + 0.5))
	# Вершины холмов: высокие точки зоны; порог снижается, пока кандидатов
	# не хватит на 14 монет (ровно 60 — критерий этапа).
	var peaks: Array[Vector3] = []
	var threshold: float = 18.0
	while threshold > 6.0:
		peaks = _hills_cells_above(heights, threshold)
		if peaks.size() >= 40:
			break
		threshold -= 2.0
	coins += _pick(peaks, 14, rng)
	# Руины: внутри стен (терраса RUINS_H).
	var inside: Array[Vector3] = []
	var rect: Rect2 = ruins["inside_rect"]
	for x: int in range(int(rect.position.x), int(rect.position.x + rect.size.x)):
		for z: int in range(int(rect.position.y), int(rect.position.y + rect.size.y)):
			inside.append(Vector3(x + 0.5, RUINS_H + 0.35, z + 0.5))
	coins += _pick(inside, 8, rng)
	# Лес: поляны без деревьев.
	var occupied := _prop_columns(props)
	var clearings: Array[Vector3] = []
	for z: int in range(-HALF, HALF + 1):
		for x: int in range(-HALF, HALF + 1):
			var cell := Vector2i(x, z)
			if occupied.has(cell):
				continue
			var h: float = heights[_idx(x, z)]
			if h <= 0.9:
				continue
			if Vector2(x + 52.0, z + 52.0).length() < 40.0:
				clearings.append(Vector3(x + 0.5, h + 0.35, z + 0.5))
	coins += _pick(clearings, 6, rng)
	# Пирс и лодочки.
	coins.append(Vector3(5.5, 1.35, 71.5))
	coins.append(Vector3(6.5, 1.35, 71.5))
	for boat: Vector3 in pier["boats"]:
		coins.append(boat + Vector3(0.0, 0.15, 0.0))
	return coins


## Точки зоны холмов не ниже порога (кандидаты монет на вершинах).
static func _hills_cells_above(heights: PackedFloat32Array, threshold: float) -> Array[Vector3]:
	var cells: Array[Vector3] = []
	for z: int in range(-HALF, HALF + 1):
		for x: int in range(-HALF, HALF + 1):
			var h: float = heights[_idx(x, z)]
			if h >= threshold and Vector2(x + 58.0, z - 42.0).length() < 42.0:
				cells.append(Vector3(x + 0.5, h + 0.35, z + 0.5))
	return cells


## Детерминированный выбор n элементов (Fisher–Yates по RNG).
static func _pick(source: Array[Vector3], n: int, rng: RandomNumberGenerator) -> Array[Vector3]:
	var picked: Array[Vector3] = []
	var count: int = mini(n, source.size())
	if count == 0:
		return picked
	var pool: Array[Vector3] = source.duplicate()
	for i: int in range(count):
		var j: int = rng.randi_range(i, pool.size() - 1)
		var tmp: Vector3 = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
		picked.append(pool[i])
	return picked


## Клетки, занятые предметами (монеты туда не ставим).
static func _prop_columns(props: Array) -> Dictionary:
	var occupied: Dictionary = {}
	for prop: Dictionary in props:
		var pos: Vector3 = prop["pos"]
		var type := String(prop["type"])
		if type == "grass_tuft" or type == "flower" or type == "pebble":
			continue
		occupied[Vector2i(int(floor(pos.x)), int(floor(pos.z)))] = true
	return occupied


# --- Мобы (раздел 8; траектории — чистые функции в mob_motion.gd) ---

static func _mobs(heights: PackedFloat32Array, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var mobs: Array[Dictionary] = []
	var spawn_id := 1
	# Птицы: лес и холмы (кружат над землёй).
	for center: Vector2 in [
		Vector2(-64, -64), Vector2(-40, -70), Vector2(-30, -42),
		Vector2(-70, -30), Vector2(-52, -18), Vector2(-60, 20),
		Vector2(-76, 50), Vector2(-42, 60),
	]:
		var ground := _nearest_land(heights, int(center.x), int(center.y), 1.0)
		mobs.append({
			"kind": "bird", "spawn_id": spawn_id,
			"center": ground, "radius": rng.randf_range(4.0, 8.0),
			"height": rng.randf_range(2.0, 4.0),
			"period": rng.randf_range(24.0, 40.0),
			"phase": rng.randf_range(0.0, TAU),
			"direction": 1 if rng.randf() < 0.5 else -1,
		})
		spawn_id += 1
	# Зверьки: луг у площади и берег озера (маршрут по земле).
	for center: Vector2 in [
		Vector2(30, 12), Vector2(42, -4), Vector2(26, -18),
		Vector2(20, 22), Vector2(16, 72), Vector2(-2, 70),
	]:
		var base := _nearest_land(heights, int(center.x), int(center.y), 0.5)
		var points: Array[Vector3] = []
		var count: int = rng.randi_range(3, 5)
		for i: int in range(count):
			var angle: float = TAU * i / float(count) + rng.randf_range(-0.4, 0.4)
			var dist: float = rng.randf_range(4.0, 8.0)
			var waypoint := _nearest_land(
				heights, int(base.x + cos(angle) * dist), int(base.z + sin(angle) * dist), 0.5
			)
			points.append(waypoint)
		mobs.append({
			"kind": "critter", "spawn_id": spawn_id, "points": points,
			"speed": rng.randf_range(1.5, 2.5),
		})
		spawn_id += 1
	# Золотые светлячки: чаща леса (парят со вспышками; уязвимость — П5).
	for center: Vector2 in [Vector2(-62, -58), Vector2(-44, -44), Vector2(-32, -62)]:
		var ground := _nearest_land(heights, int(center.x), int(center.y), 1.0)
		mobs.append({
			"kind": "firefly", "spawn_id": spawn_id,
			"center": ground + Vector3(0.0, rng.randf_range(1.0, 1.5), 0.0),
			"drift": rng.randf_range(1.5, 2.5),
			"period": rng.randf_range(3.0, 5.0),
			"phase": rng.randf_range(0.0, TAU),
		})
		spawn_id += 1
	return mobs


## Ближайшая суша не ниже min_h (поиск по кольцам — детерминирован).
static func _nearest_land(
	heights: PackedFloat32Array, x: int, z: int, min_h: float
) -> Vector3:
	for radius: int in range(0, 24):
		for dx: int in range(-radius, radius + 1):
			for dz: int in range(-radius, radius + 1):
				if maxf(absi(dx), absi(dz)) != radius:
					continue
				var cx: int = x + dx
				var cz: int = z + dz
				if absi(cx) > HALF or absi(cz) > HALF:
					continue
				var h: float = heights[_idx(cx, cz)]
				if h >= min_h:
					return Vector3(cx + 0.5, h, cz + 0.5)
	return Vector3(x + 0.5, 2.0, z + 0.5)


# --- Расщелина: зона и точки HangPoint (раздел 9.1) ---

static func _hang() -> Dictionary:
	var points: Array[Vector3] = []
	for x: int in range(CREVASSE_X0 + 4, CREVASSE_X1 - 3, 8):
		points.append(Vector3(x + 0.5, CREVASSE_RIM_H + 0.1, CREVASSE_Z0 - 0.5))
		points.append(Vector3(x + 0.5, CREVASSE_RIM_H + 0.1, CREVASSE_Z1 + 1.5))
	return {
		"center": Vector3(
			(CREVASSE_X0 + CREVASSE_X1) * 0.5 + 0.5, 2.5, (CREVASSE_Z0 + CREVASSE_Z1) * 0.5 + 0.5
		),
		"size": Vector3(CREVASSE_X1 - CREVASSE_X0 - 2, 6.0, CREVASSE_Z1 - CREVASSE_Z0 + 2),
		"points": points,
	}


# --- Поверхности для BFS ---

## Верхние поверхности: суша из карты высот плюс проходимые постройки
## (мостки, пирс, плоты). Деревья, стены и декор не учитываются — игрок
## ходит по земле под ними, а не по верхушкам.
static func _surface_heights(data: Dictionary, terrain_only: bool = false) -> Dictionary:
	var heights: Dictionary = {}
	var map: PackedFloat32Array = data["heights"]
	for z: int in range(-HALF, HALF + 1):
		for x: int in range(-HALF, HALF + 1):
			var h: float = map[_idx(x, z)]
			if h > 0.05:
				heights[Vector2i(x, z)] = h
	if terrain_only:
		return heights
	for prop: Dictionary in data["props"]:
		var type := String(prop["type"])
		var walk: float = 0.0
		if type == "plank_deck":
			walk = (prop["pos"] as Vector3).y + float((prop["scale"] as Vector3).y)
		elif type == "boat":
			walk = (prop["pos"] as Vector3).y + 0.35
		if walk <= 0.0:
			continue
		var pos: Vector3 = prop["pos"]
		var scale: Vector3 = prop["scale"]
		var half_x: float = scale.x * 0.5
		var half_z: float = (scale.z if type != "boat" else 1.4) * 0.5
		var yaw: float = float(prop["yaw"])
		var span_x: float = absf(cos(yaw)) * half_x + absf(sin(yaw)) * half_z
		var span_z: float = absf(sin(yaw)) * half_x + absf(cos(yaw)) * half_z
		for x: int in range(int(floor(pos.x - span_x)), int(ceil(pos.x + span_x))):
			for z: int in range(int(floor(pos.z - span_z)), int(ceil(pos.z + span_z))):
				var key := Vector2i(x, z)
				if heights.get(key, -1e9) < walk:
					heights[key] = walk
	return heights
