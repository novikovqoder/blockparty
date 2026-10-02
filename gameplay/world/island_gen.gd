# Генератор острова (раздел 6 SPEC): чистые данные без нод — рельеф из
# FastNoiseLite с фиксированным seed и RandomNumberGenerator (детерминизм:
# повторный вызов даёт тот же результат; тест — на хеш блоков).
# Остров 256 × 256 м (клетки x, z ∈ [−128, 127]), высота суши до 24 м, вокруг
# море. k — верх поверхности в половинах метра (k = 4 → верх на 2.0 м);
# k квантовано к чётным: верх колонны всегда на целом числе метров, блок
# рельефа в GridMap занимает ячейку k/2 − 1 целиком, и любые постройки сверху
# стыкуются с землёй без зазоров (меш ячейки Y — это [Y, Y+1]). Полублоки —
# только декор (кольцо костра). Колонны заполняются «верхом + видимыми
# стенками» (до самого низкого соседа), море — плоским дном на −1.0 м:
# скрытая внутренность острова не видна и коллизии не требует.
# Сцену из данных строит tools/generate_island.gd; тесты дергают этот класс.
class_name IslandGen
extends RefCounted

## Seed генерации (фиксирован; смена меняет весь остров и хеш в тесте).
const SEED_VALUE: int = 20261002
## Половина размера карты в клетках.
const HALF: int = 128
## Колонна моря: плоское дно, верх на −1.5 м.
const SEA_K: int = -3
## Уровень воды (море и озеро), м.
const SEA_LEVEL: float = -0.15
## Радиусы маски острова: внутри — суша, дальше плавный спад в море.
const ISLAND_R_IN: float = 58.0
const ISLAND_R_OUT: float = 112.0
## Каньон расщелины: прямоугольник клеток и высоты дна/кромки.
const CREVASSE_X0: int = 26
const CREVASSE_X1: int = 98
const CREVASSE_Z0: int = 52
const CREVASSE_Z1: int = 62
const CREVASSE_FLOOR_K: int = 2
const CREVASSE_RIM_K: int = 12
## Кромка держит высоту 12 в полосе 2 клетки от края и плавно сливается
## с рельефом на протяжении 5 клеток — стены без непроходимых уступов.
const CREVASSE_RIM_BAND: float = 2.0
const CREVASSE_RIM_BLEND: float = 5.0
## Мостки: две переправы из досок, настил на полблока выше кромки.
const BRIDGE_X: PackedInt32Array = [45, 76]
const BRIDGE_DECK_CELL_Y: int = 6

## Зоны (раздел 6): имя для --dev-spawn и F3, круг для названия места.
const ZONES: Array[Dictionary] = [
	{"name": "plaza", "center": Vector2(0, 4), "radius": 20.0},
	{"name": "forest", "center": Vector2(-52, -52), "radius": 44.0},
	{"name": "ruins", "center": Vector2(58, -48), "radius": 30.0},
	{"name": "hills", "center": Vector2(-58, 42), "radius": 42.0},
	{"name": "crevasse", "center": Vector2(62, 57), "radius": 42.0},
	{"name": "lake", "center": Vector2(6, 82), "radius": 26.0},
]

## Смотровые площадки (раздел 9.3): площадка 3 × 3 на 3.0 м выше базиса
## (k 20 против 14) — без подсадки не забраться, с подсадкой — можно.
const LOOKOUTS: Array[Vector2i] = [
	Vector2i(-72, 34),
	Vector2i(-52, 28),
	Vector2i(-66, 56),
	Vector2i(-44, 48),
]
const LOOKOUT_BASE_K: int = 14
const LOOKOUT_TOP_K: int = 20


## Полные данные острова (детерминированы): columns, extras, water, hang,
## stones, spawn_zones, coins (ровно 60), mobs, poi, bounds.
static func generate() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_VALUE
	var shape := _noise(SEED_VALUE, 1.0 / 90.0, 4)
	var detail := _noise(SEED_VALUE + 1, 1.0 / 28.0, 2)
	var columns: Dictionary = {}
	for x: int in range(-HALF, HALF):
		for z: int in range(-HALF, HALF):
			columns[Vector2i(x, z)] = _base_column(x, z, shape, detail)
	_apply_zones(columns)
	_smooth_cliffs(columns)
	_carve_crevasse(columns)
	_lookouts(columns)
	_apply_materials(columns)
	var data := {
		"columns": columns,
		"extras": [],
		"water": {
			"sea": {"center": Vector2(0, 0), "size": Vector2(HALF * 2, HALF * 2), "level": SEA_LEVEL},
			"lake": {"center": Vector2(6, 82), "size": Vector2(30, 30), "level": SEA_LEVEL},
		},
	}
	var extras: Array = data["extras"]
	# Точки интереса резервируются до посадки деревьев: на клетках камней,
	# спавнов и построек ничего не вырастает.
	var stones: Array[Vector3] = []
	var spawns: Dictionary = {}
	var reserved: Dictionary = _points_of_interest(columns, stones, spawns)
	_trees_and_rocks(columns, extras, rng, reserved)
	_bridges(extras)
	var ruins: Dictionary = _ruins(extras, rng)
	var pier: Dictionary = _pier_and_boats(extras)
	var fire: Dictionary = _campfire_and_board(extras)
	data["stones"] = stones
	data["spawn_zones"] = spawns
	data["coins"] = _coins(columns, extras, ruins, pier, rng)
	data["mobs"] = _mobs(columns, rng)
	data["hang"] = _hang()
	data["poi"] = {"ruins": ruins, "pier": pier, "campfire": fire}
	data["bounds"] = HALF - 0.5
	return data


## Список блоков GridMap: {cell: Vector3i, block: int}, отсортирован —
## порядок стабилен для хеша и сборки сцены.
static func cells(data: Dictionary) -> Array[Dictionary]:
	var grid: Dictionary = {}
	var columns: Dictionary = data["columns"]
	for key: Vector2i in columns:
		_fill_column(grid, key, columns[key], columns)
	for extra: Dictionary in data["extras"]:
		grid[extra["cell"]] = extra["block"]
	var list: Array[Dictionary] = []
	for cell: Vector3i in grid:
		list.append({"cell": cell, "block": grid[cell]})
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["cell"] < b["cell"])
	return list


## Хеш содержимого GridMap (тест детерминизма: два вызова generate → хеши
## совпадают; также ловит незапланированное изменение генератора).
static func block_hash(data: Dictionary) -> int:
	var h: int = SEED_VALUE
	for entry: Dictionary in cells(data):
		var cell: Vector3i = entry["cell"]
		h = hash([h, cell.x, cell.y, cell.z, entry["block"]])
	return h


## Достижимость пешком (тесты «все зоны достижимы», «смотровые — нет»):
#  заливка от спавна площади по верхним поверхностям, подъём не больше 1.0 м
#  (высота прыжка ~1.34, ступени 0.5 — автоподъём). Море не проходимо —
#  проверяется именно сухопутная связность острова; подсадка на голову
#  требует второго игрока и в заливку не входит.
static func walkable_reach(data: Dictionary) -> Dictionary:
	var heights := _surface_heights(data)
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
			if heights[next] - h0 <= 1.0 + 0.01:
				visited[next] = true
				queue.append(next)
	return visited


## Верхняя поверхность клетки (м) или NaN, если клетки нет.
static func top_of(data: Dictionary, x: int, z: int) -> float:
	var heights := _surface_heights(data)
	return heights.get(Vector2i(x, z), NAN)


# --- Базовый рельеф ---

static func _noise(seed_value: int, frequency: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	return noise


## Шум + круговая маска → базовая колонна (до зон). land_t < 0.17 — море,
#  у кромки пляж k = 0, далее подъём до 48 (24 м).
static func _base_column(
	x: int, z: int, shape: FastNoiseLite, detail: FastNoiseLite
) -> Dictionary:
	var e: float = shape.get_noise_2d(x, z) * 0.7 + detail.get_noise_2d(x, z) * 0.3
	var r := Vector2(x, z).length()
	var mask: float = 1.0 - smoothstep(ISLAND_R_IN, ISLAND_R_OUT, r)
	var land_t: float = (e * 0.5 + 0.5) * mask
	if land_t < 0.17:
		return {"k": SEA_K, "top": BlockLibrary.Block.SAND, "under": BlockLibrary.Block.SAND}
	var k := 0
	if land_t >= 0.19:
		# Квантование к чётным k (шаг рельефа 1.0 м): прыжка ~1.34 м хватает
		# на ступень, а постройки встают на землю без полуметровых зазоров.
		k = clampi(2 + 2 * int(round((land_t - 0.19) / 0.81 * 23.0)), 2, 48)
	return {"k": k, "top": 0, "under": 0}


## Зоны меняют высоты: площадь и руины — плоские террасы (там всегда суша),
#  холмы усилены к центру, лес пологий, озеро вырезано с пляжем. Расщелина
#  и смотровые прорезаются после выравнивания ступеней (_smooth_cliffs) —
#  их обрывы запланированы, а весь остальной остров проходим пешком.
static func _apply_zones(columns: Dictionary) -> void:
	for key: Vector2i in columns:
		var column: Dictionary = columns[key]
		var x: int = key.x
		var z: int = key.y
		var is_land: bool = int(column["k"]) > SEA_K
		# Холмы: усиление высоты к центру зоны.
		var d_hills: float = Vector2(x + 58.0, z - 42.0).length()
		if is_land and d_hills < 42.0:
			var boost: float = 1.0 - d_hills / 42.0
			column["k"] = maxi(int(column["k"]) + 2 * int(round(boost * boost * 13.0)), 6)
		# Лес: пологий, без обрывов.
		if is_land and Vector2(x + 52.0, z + 52.0).length() < 40.0:
			column["k"] = clampi(int(column["k"]), 4, 12)
		# Площадь: плоская терраса (запланированная суша в центре острова).
		if Vector2(x, z - 4.0).length() < 18.0:
			column["k"] = 4
		# Руины: ровная терраса под стенами (вытянута к площади).
		if Vector2(x - 58.0, z + 48.0).length() < 24.0:
			column["k"] = 6
		# Озеро: котловина с водой и песчаной кромкой.
		var d_lake: float = Vector2(x - 6.0, z - 82.0).length()
		if d_lake < 16.0:
			column["k"] = SEA_K
			column["top"] = BlockLibrary.Block.SAND
			column["under"] = BlockLibrary.Block.SAND
		elif is_land and d_lake < 21.0:
			column["k"] = mini(int(column["k"]), 2)


## Выровнять крутые ступени: после квантования шума соседние колонны могут
## отличаться больше чем на 1.0 м (2 полублока) — такие «стены» ломают
## проходимость. Проходы в обе стороны капают высоту колонны до
## «минимальный сосед + 2», пока рельеф не станет лестницей с шагом ≤ 1.0 м
## (высота прыжка ~1.34 м). Море не участвует — береговые обрывы остаются.
static func _smooth_cliffs(columns: Dictionary) -> void:
	var keys: Array[Vector2i] = []
	for x: int in range(-HALF, HALF):
		for z: int in range(-HALF, HALF):
			keys.append(Vector2i(x, z))
	var changed := true
	var iteration := 0
	while changed and iteration < 12:
		changed = false
		iteration += 1
		var reverse: bool = iteration % 2 == 0
		for index: int in range(keys.size()):
			var key: Vector2i = keys[keys.size() - 1 - index] if reverse else keys[index]
			var column: Dictionary = columns[key]
			var k: int = int(column["k"])
			if k <= SEA_K:
				continue
			var min_neighbor: int = 1 << 30
			for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var neighbor = columns.get(key + dir)
				if neighbor == null:
					continue
				var nk: int = int(neighbor["k"])
				if nk > SEA_K:
					min_neighbor = mini(min_neighbor, nk)
			if min_neighbor < (1 << 30) and k > min_neighbor + 2:
				column["k"] = min_neighbor + 2
				changed = true


## Расщелина: дно каньона и приподнятая кромка, плавно сливающаяся
## с рельефом. Прорезается после выравнивания — стены каньона остаются
## непроходимыми, переправа только по мосткам.
static func _carve_crevasse(columns: Dictionary) -> void:
	for key: Vector2i in columns:
		var column: Dictionary = columns[key]
		var x: int = key.x
		var z: int = key.y
		var is_land: bool = int(column["k"]) > SEA_K
		var in_canyon: bool = x >= CREVASSE_X0 and x <= CREVASSE_X1 \
			and z >= CREVASSE_Z0 and z <= CREVASSE_Z1
		if in_canyon:
			column["k"] = CREVASSE_FLOOR_K
			column["top"] = BlockLibrary.Block.STONE
			column["under"] = BlockLibrary.Block.STONE
		elif is_land:
			var d: float = _dist_to_crevasse(x, z)
			if d <= CREVASSE_RIM_BAND:
				column["k"] = CREVASSE_RIM_K
			elif d <= CREVASSE_RIM_BAND + CREVASSE_RIM_BLEND:
				var natural: int = int(column["k"])
				var t: float = (d - CREVASSE_RIM_BAND) / CREVASSE_RIM_BLEND
				# Округление к чётному — вся сетка остаётся с шагом 1.0 м.
				column["k"] = int(round(lerpf(CREVASSE_RIM_K, natural, t) * 0.5)) * 2


## Материалы по высоте: песок у воды, трава, снег на вершинах. Клетки
## с уже заданным верхом (море/озеро, дно расщелины, смотровые) не трогаем.
static func _apply_materials(columns: Dictionary) -> void:
	for key: Vector2i in columns:
		var column: Dictionary = columns[key]
		if int(column["top"]) != 0:
			continue
		var k: int = int(column["k"])
		if k <= 3:
			column["top"] = BlockLibrary.Block.SAND
			column["under"] = BlockLibrary.Block.SAND
		elif k >= 41:
			column["top"] = BlockLibrary.Block.SNOW
			column["under"] = BlockLibrary.Block.STONE
		else:
			column["top"] = BlockLibrary.Block.GRASS
			column["under"] = BlockLibrary.Block.DIRT


static func _dist_to_crevasse(x: int, z: int) -> float:
	var dx: float = maxf(maxf(CREVASSE_X0 - x, 0.0), x - CREVASSE_X1)
	var dz: float = maxf(maxf(CREVASSE_Z0 - z, 0.0), z - CREVASSE_Z1)
	return Vector2(dx, dz).length()


# --- Заполнение колонн блоками ---

## Верх колонны + стенки вниз до самого низкого соседа (минус запас 1 м):
#  скрытые внутренние блоки не ставятся — их не видно и они лишь грузят GridMap.
static func _fill_column(
	grid: Dictionary, key: Vector2i, column: Dictionary, columns: Dictionary
) -> void:
	var k: int = int(column["k"])
	var x: int = key.x
	var z: int = key.y
	if k == SEA_K:
		grid[Vector3i(x, -2, z)] = BlockLibrary.Block.SAND
		return
	var bottom_limit := _neighbor_bottom(columns, x, z)
	var top_block: int = int(column["top"])
	var under_block: int = int(column["under"])
	# Верхний блок рельефа: ячейка k/2 − 1, он занимает [k/2 − 1, k/2],
	# то есть верх точно на k * 0.5 м (k чётное).
	var top_cell: int = k / 2 - 1
	grid[Vector3i(x, top_cell, z)] = top_block
	_fill_range(grid, x, z, top_cell - 1, bottom_limit, top_block, under_block)


## Нижняя граница заполнения: минимум верхов соседних колонн − 1 м.
static func _neighbor_bottom(columns: Dictionary, x: int, z: int) -> float:
	var lowest: float = 1e9
	for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var neighbor = columns.get(Vector2i(x + dir.x, z + dir.y))
		if neighbor == null:
			lowest = minf(lowest, -1.5)  # за краем карты — уровень дна моря
		else:
			lowest = minf(lowest, int(neighbor["k"]) * 0.5)
	return lowest - 1.0


static func _fill_range(
	grid: Dictionary, x: int, z: int, from_y: int, bottom_limit: float,
	top_block: int, under_block: int,
) -> void:
	if top_block == BlockLibrary.Block.SAND:
		under_block = BlockLibrary.Block.SAND
	elif top_block == BlockLibrary.Block.SNOW:
		under_block = BlockLibrary.Block.STONE
	var y_min: int = int(floor(bottom_limit + 0.5)) - 1
	var depth := 0
	var y := from_y
	while y > y_min:
		var block: int = under_block
		if top_block == BlockLibrary.Block.GRASS and depth > 2:
			block = BlockLibrary.Block.STONE
		grid[Vector3i(x, y, z)] = block
		depth += 1
		y -= 1


# --- Деревья, камни ---

static func _trees_and_rocks(
	columns: Dictionary, extras: Array, rng: RandomNumberGenerator, reserved: Dictionary
) -> void:
	var forest := Vector2(-52.0, -52.0)
	var trees: Dictionary = {}
	for x: int in range(-HALF, HALF):
		for z: int in range(-HALF, HALF):
			if reserved.has(Vector2i(x, z)):
				continue
			var column: Dictionary = columns[Vector2i(x, z)]
			var k: int = int(column["k"])
			if int(column["top"]) != BlockLibrary.Block.GRASS:
				continue
			# Первый блок над поверхностью k * 0.5: ячейка k/2 (блок [k/2, k/2+1]).
			var first: int = k / 2
			var d_forest: float = Vector2(x, z).distance_to(forest)
			if d_forest < 40.0:
				if rng.randf() < 0.05 and _no_trees_near(trees, x, z, 2):
					trees[Vector2i(x, z)] = true
					_tree(extras, x, z, first, rng.randi_range(3, 4))
			elif Vector2(x + 58.0, z - 42.0).length() < 42.0 and k >= 8:
				if rng.randf() < 0.012:
					extras.append({"cell": Vector3i(x, first, z), "block": BlockLibrary.Block.STONE})
			elif d_forest < 56.0 and Vector2(x, z - 4.0).length() > 20.0:
				if rng.randf() < 0.01 and _no_trees_near(trees, x, z, 3):
					trees[Vector2i(x, z)] = true
					_tree(extras, x, z, first, rng.randi_range(3, 4))


static func _no_trees_near(trees: Dictionary, x: int, z: int, radius: int) -> bool:
	for dx: int in range(-radius, radius + 1):
		for dz: int in range(-radius, radius + 1):
			if trees.has(Vector2i(x + dx, z + dz)):
				return false
	return true


## Дерево: ствол 3–4 блока + крона из листвы (кольца 3 × 3 и «плюс» сверху).
static func _tree(extras: Array, x: int, z: int, first: int, trunk: int) -> void:
	for y: int in range(first, first + trunk):
		extras.append({"cell": Vector3i(x, y, z), "block": BlockLibrary.Block.TRUNK})
	var crown: int = first + trunk - 2
	for dy: int in range(0, 2):
		for dx: int in range(-1, 2):
			for dz: int in range(-1, 2):
				if dx == 0 and dz == 0:
					continue
				extras.append({
					"cell": Vector3i(x + dx, crown + dy, z + dz),
					"block": BlockLibrary.Block.LEAVES,
				})
	for dx: int in range(-1, 2):
		for dz: int in range(-1, 2):
			if absi(dx) + absi(dz) <= 1:
				extras.append({
					"cell": Vector3i(x + dx, crown + 2, z + dz),
					"block": BlockLibrary.Block.LEAVES,
				})


# --- Мостки, смотровые, руины, пирс, костёр ---

## Две переправы через расщелину: настил из досок на верху кромки
#  (клетка 6 → верх 6.5 м; на кромке блок заменяет её полублок).
static func _bridges(extras: Array) -> void:
	for bx: int in BRIDGE_X:
		for x: int in [bx, bx + 1]:
			for z: int in range(CREVASSE_Z0 - 2, CREVASSE_Z1 + 3):
				extras.append({
					"cell": Vector3i(x, BRIDGE_DECK_CELL_Y, z),
					"block": BlockLibrary.Block.PLANKS,
					"walk": true,
				})


## Смотровые: базис-поляна k 14, площадка 3 × 3 на k 20 — уступ ровно 3.0 м.
static func _lookouts(columns: Dictionary) -> void:
	for center: Vector2i in LOOKOUTS:
		for dx: int in range(-7, 8):
			for dz: int in range(-7, 8):
				var cell := Vector2i(center.x + dx, center.y + dz)
				if not columns.has(cell):
					continue
				var platform: bool = absi(dx) <= 1 and absi(dz) <= 1
				var column: Dictionary = columns[cell]
				column["k"] = LOOKOUT_TOP_K if platform else LOOKOUT_BASE_K
				column["top"] = BlockLibrary.Block.STONE if platform else BlockLibrary.Block.GRASS
				column["under"] = BlockLibrary.Block.STONE if platform else BlockLibrary.Block.DIRT


## Руины: прямоугольник стен с проломами, ворота с башнями (проём закрыт
#  тёмным кирпичом — откроется на П5), перед воротами три плиты, за воротами
#  сундук; внутри немного камня-обломков.
static func _ruins(extras: Array, rng: RandomNumberGenerator) -> Dictionary:
	var x0: int = 46
	var x1: int = 70
	var z0: int = -58
	var z1: int = -38
	# Терраса руин k=6 (верх 3.0): стены стоят с ячейки 3, блок [3, 4].
	var base_first: int = 3
	for x: int in range(x0, x1 + 1):
		for z: int in range(z0, z1 + 1):
			var on_wall: bool = x == x0 or x == x1 or z == z0 or z == z1
			if not on_wall:
				continue
			# Ворота на стороне площади: проём x 57..58 закрыт тёмным кирпичом.
			if z == z1 and x >= 57 and x <= 58:
				for y: int in range(base_first, base_first + 4):
					extras.append({
						"cell": Vector3i(x, y, z),
						"block": BlockLibrary.Block.RUIN_BRICK_DARK,
					})
				continue
			var height: int = 2 + rng.randi_range(0, 1)
			if rng.randf() < 0.3:
				height = 0  # пролом в стене
			for y: int in range(base_first, base_first + height):
				extras.append({
					"cell": Vector3i(x, y, z),
					"block": BlockLibrary.Block.RUIN_BRICK,
				})
	# Башни по сторонам ворот.
	for tower_x: int in [55, 60]:
		for y: int in range(base_first, base_first + 5):
			extras.append({"cell": Vector3i(tower_x, y, z1), "block": BlockLibrary.Block.RUIN_BRICK})
	# Обломки внутри.
	for i: int in range(10):
		var rx: int = rng.randi_range(x0 + 2, x1 - 2)
		var rz: int = rng.randi_range(z0 + 2, z1 - 2)
		extras.append({"cell": Vector3i(rx, base_first, rz), "block": BlockLibrary.Block.STONE})
	return {
		"center": Vector3(58, 3.0, -48),
		"gate_center": Vector3(58, 3.0, float(z1)),
		"chest": Vector3(58, 3.0, -50),
		"plates": [
			Vector3(54, 3.0, z1 - 3),
			Vector3(58, 3.0, z1 - 3),
			Vector3(62, 3.0, z1 - 3),
		],
		"inside_rect": Rect2(Vector2(x0 + 1, z0 + 1), Vector2(x1 - x0 - 1, z1 - z0 - 1)),
	}


## Пирс в озеро (настил на 0.5 м над водой, столбики) и две лодочки-плота.
static func _pier_and_boats(extras: Array) -> Dictionary:
	for x: int in [5, 6]:
		for z: int in range(61, 73):
			extras.append({
				"cell": Vector3i(x, 0, z), "block": BlockLibrary.Block.PLANKS, "walk": true,
			})
			if z % 3 == 0:
				extras.append({"cell": Vector3i(x, -1, z), "block": BlockLibrary.Block.TRUNK})
	for boat: Vector2i in [Vector2i(13, 74), Vector2i(-3, 78)]:
		for dx: int in range(0, 3):
			for dz: int in range(0, 2):
				extras.append({
					"cell": Vector3i(boat.x + dx, 0, boat.y + dz),
					"block": BlockLibrary.Block.PLANKS if dx == 1 else BlockLibrary.Block.TRUNK,
					"walk": true,
				})
	return {
		"deck_end": Vector3(6.0, 1.0, 71.5),
		"boats": [Vector3(14.0, 1.0, 74.5), Vector3(-2.0, 1.0, 78.5)],
	}


## Костёр на площади: каменное кольцо, лавки-брёвна вокруг, доска события
#  севернее. Сидение и огонь-логика — П5; здесь геометрия и позиции.
static func _campfire_and_board(extras: Array) -> Dictionary:
	var fire := Vector2i(0, 2)
	var plaza_top_cell: int = 4 / 2  # площадь k=4: полублок в cell 2, верх 2.0
	for i: int in range(8):
		var angle: float = TAU * i / 8.0
		var ring := Vector2(fire) + Vector2(cos(angle), sin(angle)) * 1.5
		extras.append({
			"cell": Vector3i(int(round(ring.x)), plaza_top_cell, int(round(ring.y))),
			"block": BlockLibrary.Block.STONE_HALF,
		})
	var benches: Array[Vector3] = []
	for i: int in range(8):
		var angle: float = TAU * i / 8.0 + PI / 8.0
		var bench := Vector2(fire) + Vector2(cos(angle), sin(angle)) * 4.5
		var bx: int = int(round(bench.x))
		var bz: int = int(round(bench.y))
		extras.append({"cell": Vector3i(bx, plaza_top_cell, bz), "block": BlockLibrary.Block.PLANKS})
		benches.append(Vector3(bx + 0.5, 3.0, bz + 0.5))
	# Доска события: щит из досок (x −1..1) на двух столбах по бокам (x ±2),
	# оба ярусами с ячейки 2 — стоят на площади, щит держится на столбах.
	for pillar_x: int in [-2, 2]:
		for y: int in range(plaza_top_cell, plaza_top_cell + 2):
			extras.append({"cell": Vector3i(pillar_x, y, -6), "block": BlockLibrary.Block.TRUNK})
	for dx: int in range(-1, 2):
		for y: int in range(plaza_top_cell, plaza_top_cell + 2):
			extras.append({"cell": Vector3i(dx, y, -6), "block": BlockLibrary.Block.PLANKS})
	return {
		"center": Vector3(0.5, 2.0, 2.5),
		"benches": benches,
		"board": Vector3(0.5, 3.0, -5.5),
	}


## Камни духа (по одному на зону) и точки появления --dev-spawn. Возвращает
## множество зарезервированных клеток (по ним не растут деревья и не ставятся
## камни-декорации), чтобы точка интереса не оказалась внутри ствола.
static func _points_of_interest(
	columns: Dictionary, stones: Array[Vector3], spawns: Dictionary
) -> Dictionary:
	var reserved: Dictionary = {}
	var stone_cells: Array[Vector2i] = [
		Vector2i(0, 12), Vector2i(-52, -38), Vector2i(58, -32),
		Vector2i(-46, 32), Vector2i(40, 46), Vector2i(4, 66),
	]
	for cell: Vector2i in stone_cells:
		_ensure_land(columns, cell, 2)
		reserved[cell] = true
		stones.append(Vector3(cell.x + 0.5, int(columns[cell]["k"]) * 0.5, cell.y + 0.5))
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
		_ensure_land(columns, cell, 2)
		reserved[cell] = true
		spawns[zone] = Vector3(cell.x + 0.5, int(columns[cell]["k"]) * 0.5 + 0.1, cell.y + 0.5)
	return reserved


## Поднять колонну до минимальной высоты, если точка попала в воду/пляж.
static func _ensure_land(columns: Dictionary, cell: Vector2i, min_k: int) -> void:
	if not columns.has(cell):
		return
	var column: Dictionary = columns[cell]
	if int(column["k"]) < min_k:
		column["k"] = min_k
		column["top"] = BlockLibrary.Block.GRASS
		column["under"] = BlockLibrary.Block.DIRT


# --- Монеты (ровно 60, раздел 8) ---

static func _coins(
	columns: Dictionary, extras: Array, ruins: Dictionary, pier: Dictionary,
	rng: RandomNumberGenerator,
) -> Array[Vector3]:
	var coins: Array[Vector3] = []
	# Смотровые: по 4 на площадке (верх 10.0 м).
	for center: Vector2i in LOOKOUTS:
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			coins.append(Vector3(
				center.x + offset.x + 0.5, LOOKOUT_TOP_K * 0.5 + 0.35, center.y + offset.y + 0.5
			))
	# Мостки: по 6 вдоль каждой переправы (настил — ячейка 6, верх 7.0).
	for bx: int in BRIDGE_X:
		for i: int in range(6):
			var z: int = CREVASSE_Z0 - 1 + i * 2
			coins.append(Vector3(bx + 0.5, BRIDGE_DECK_CELL_Y + 1.0 + 0.35, z + 0.5))
	# Вершины холмов: верхние колонны зоны.
	var peaks: Array[Vector3] = []
	for x: int in range(-HALF, HALF):
		for z: int in range(-HALF, HALF):
			var column: Dictionary = columns[Vector2i(x, z)]
			var k: int = int(column["k"])
			if k >= 36 and Vector2(x + 58.0, z - 42.0).length() < 42.0:
				peaks.append(Vector3(x + 0.5, k * 0.5 + 0.35, z + 0.5))
	if peaks.size() < 14:
		for x: int in range(-HALF, HALF):
			for z: int in range(-HALF, HALF):
				var column: Dictionary = columns[Vector2i(x, z)]
				var k: int = int(column["k"])
				if k >= 28 and Vector2(x + 58.0, z - 42.0).length() < 42.0:
					peaks.append(Vector3(x + 0.5, k * 0.5 + 0.35, z + 0.5))
	coins += _pick(peaks, 14, rng)
	# Руины: внутри стен.
	var inside: Array[Vector3] = []
	var rect: Rect2 = ruins["inside_rect"]
	for x: int in range(int(rect.position.x), int(rect.position.x + rect.size.x)):
		for z: int in range(int(rect.position.y), int(rect.position.y + rect.size.y)):
			inside.append(Vector3(x + 0.5, 6 * 0.5 + 0.35, z + 0.5))
	coins += _pick(inside, 8, rng)
	# Лес: поляны без деревьев.
	var occupied := _extra_columns(extras)
	var clearings: Array[Vector3] = []
	for x: int in range(-HALF, HALF):
		for z: int in range(-HALF, HALF):
			var cell := Vector2i(x, z)
			if occupied.has(cell):
				continue
			var column: Dictionary = columns[cell]
			if int(column["top"]) != BlockLibrary.Block.GRASS:
				continue
			if Vector2(x + 52.0, z + 52.0).length() < 40.0:
				clearings.append(Vector3(x + 0.5, int(column["k"]) * 0.5 + 0.35, z + 0.5))
	coins += _pick(clearings, 6, rng)
	# Пирс и лодочки (настил — ячейка 0, верх 1.0; монета над ним).
	coins.append(Vector3(5.5, 1.35, 71.5))
	coins.append(Vector3(6.5, 1.35, 71.5))
	for boat: Vector3 in pier["boats"]:
		coins.append(boat + Vector3(0.0, 0.35, 0.0))
	return coins


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


## Клетки, занятые доп-блоками (деревья, стены) — монеты туда не ставим.
static func _extra_columns(extras: Array) -> Dictionary:
	var occupied: Dictionary = {}
	for extra: Dictionary in extras:
		var cell: Vector3i = extra["cell"]
		occupied[Vector2i(cell.x, cell.z)] = true
	return occupied


# --- Мобы (раздел 8; траектории — чистые функции в mob_motion.gd) ---

static func _mobs(columns: Dictionary, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var mobs: Array[Dictionary] = []
	var spawn_id := 1
	# Птицы: лес и холмы (кружат над землёй).
	for center: Vector2 in [
		Vector2(-64, -64), Vector2(-40, -70), Vector2(-30, -42),
		Vector2(-70, -30), Vector2(-52, -18), Vector2(-60, 20),
		Vector2(-76, 50), Vector2(-42, 60),
	]:
		var ground := _nearest_land(columns, int(center.x), int(center.y), 4)
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
		var base := _nearest_land(columns, int(center.x), int(center.y), 2)
		var points: Array[Vector3] = []
		var count: int = rng.randi_range(3, 5)
		for i: int in range(count):
			var angle: float = TAU * i / float(count) + rng.randf_range(-0.4, 0.4)
			var dist: float = rng.randf_range(4.0, 8.0)
			var waypoint := _nearest_land(
				columns, int(base.x + cos(angle) * dist), int(base.z + sin(angle) * dist), 2
			)
			points.append(waypoint)
		mobs.append({
			"kind": "critter", "spawn_id": spawn_id, "points": points,
			"speed": rng.randf_range(1.5, 2.5),
		})
		spawn_id += 1
	# Золотые светлячки: чаща леса (парят со вспышками; уязвимость — П5).
	for center: Vector2 in [Vector2(-62, -58), Vector2(-44, -44), Vector2(-32, -62)]:
		var ground := _nearest_land(columns, int(center.x), int(center.y), 4)
		mobs.append({
			"kind": "firefly", "spawn_id": spawn_id,
			"center": ground + Vector3(0.0, rng.randf_range(1.0, 1.5), 0.0),
			"drift": rng.randf_range(1.5, 2.5),
			"period": rng.randf_range(3.0, 5.0),
			"phase": rng.randf_range(0.0, TAU),
		})
		spawn_id += 1
	return mobs


## Ближайшая суша не ниже min_k (поиск по кольцам — детерминирован).
static func _nearest_land(columns: Dictionary, x: int, z: int, min_k: int) -> Vector3:
	for radius: int in range(0, 12):
		for dx: int in range(-radius, radius + 1):
			for dz: int in range(-radius, radius + 1):
				if maxf(absi(dx), absi(dz)) != radius:
					continue
				var cell := Vector2i(x + dx, z + dz)
				if not columns.has(cell):
					continue
				var column: Dictionary = columns[cell]
				if int(column["k"]) >= min_k:
					return Vector3(cell.x + 0.5, int(column["k"]) * 0.5, cell.y + 0.5)
	return Vector3(x + 0.5, 2.0, z + 0.5)


# --- Расщелина: зона и точки HangPoint (раздел 9.1) ---

static func _hang() -> Dictionary:
	var points: Array[Vector3] = []
	for x: int in range(CREVASSE_X0 + 4, CREVASSE_X1 - 3, 8):
		points.append(Vector3(x + 0.5, CREVASSE_RIM_K * 0.5 + 0.1, CREVASSE_Z0 - 0.5))
		points.append(Vector3(x + 0.5, CREVASSE_RIM_K * 0.5 + 0.1, CREVASSE_Z1 + 1.5))
	return {
		"center": Vector3(
			(CREVASSE_X0 + CREVASSE_X1) * 0.5 + 0.5, 2.5, (CREVASSE_Z0 + CREVASSE_Z1) * 0.5 + 0.5
		),
		"size": Vector3(CREVASSE_X1 - CREVASSE_X0 - 2, 6.0, CREVASSE_Z1 - CREVASSE_Z0 + 2),
		"points": points,
	}


# --- Поверхности для BFS ---

## Верхние поверхности клеток: колонны суши (море не в счёт) и проходимые
## постройки (мостки, пирс, плоты). Деревья, стены и декор не учитываются —
## игрок ходит по земле под ними, а не по верхушкам.
static func _surface_heights(data: Dictionary) -> Dictionary:
	var heights: Dictionary = {}
	var columns: Dictionary = data["columns"]
	for key: Vector2i in columns:
		var k: int = int(columns[key]["k"])
		if k > SEA_K:
			heights[key] = k * 0.5
	for extra: Dictionary in data["extras"]:
		if not extra.get("walk", false):
			continue
		var cell: Vector3i = extra["cell"]
		var top: float = cell.y + (0.5 if BlockLibrary.is_half(int(extra["block"])) else 1.0)
		var key := Vector2i(cell.x, cell.z)
		if heights.get(key, -1e9) < top:
			heights[key] = top
	return heights
