# Генератор острова (раздел 6 SPEC, стиль low-poly): чистые данные без нод —
# карта высот 257 × 257 точек с шагом 1 м из FastNoiseLite с фиксированным
# seed и RandomNumberGenerator (детерминизм: повторный вызов даёт тот же
# результат; тест — на хеш высот и списка предметов). Суша 1–22 м, вокруг
# море с плавным спадом к берегу. Меш рельефа и коллизия (HeightMapShape3D)
# строит terrain.gd из той же карты; крутые перепады ≥ 0.9 м на метр —
# непроходимые стены, их прикрывают предметы-призмы (prop_meshes.gd):
# уступ получает чистую вертикальную стену, а не «лестницу» рельефа.
# Предметы раскладываются по правилам зон тем же seed; зоны, POI,
# точки мобов и камни духа сохраняют расположение кубической
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

## Сила сглаживания карты высот (доработка-2 П5.13, П1, _smooth_pass).
const SMOOTH_STRENGTH: float = 0.6

## Гидравлическая эрозия (П5.13, блок 3): количество капель и параметры
## переноса осадка. Подобраны под сетку 1 м: промоины глубиной ~0.3–1.2 м
## переживают второй проход _limit_slopes (стенки < 0.9 м/м).
const EROSION_DROPLETS: int = 9000
const EROSION_MAX_STEPS: int = 32
const EROSION_BRUSH: int = 2
const EROSION_INERTIA: float = 0.06
const EROSION_CAPACITY: float = 3.4
const EROSION_ERODE: float = 0.32
const EROSION_DEPOSIT: float = 0.26
const EROSION_EVAPORATE: float = 0.02
## Уклон запуска капли (м на клетку): эрозия — только на склонах.
const EROSION_SPAWN_SLOPE: float = 0.22
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

## Лесной овраг (П5.7, блок 2): сухое русло поперёк лесной тропы, через
## которое переброшен мостик из брёвен (_forest_landmarks). Ось задана
## серединой (точка моста на тропе) и направлением; глубина — с плоским
## дном и плавной кромкой (1 − smoothstep), сужение к концам за
## GULLY_TAPER. Дно ложится во «влажную землю» ForestGround (h < 3.2),
## стенки — в «камень» по уклону.
const GULLY_MID: Vector2 = Vector2(-48.1, -45.4)
const GULLY_DIR: Vector2 = Vector2(-0.809, 0.588)
const GULLY_HALF_LEN: float = 7.0
const GULLY_HALF_W: float = 1.7
const GULLY_DEPTH: float = 2.1
const GULLY_TAPER: float = 2.5

## Поляна с огромным деревом: центр и радиус голой земли вокруг ствола.
const GIANT_CELL: Vector2i = Vector2i(-41, -66)
const GIANT_CLEAR_R: int = 7

## Чаша озера (доработка П5.13, вынесены для самопроверки воды): d меньше
## LAKE_BASIN_R — дно −1.2, до LAKE_BEACH_R — пологий пляж. Плоскость воды
## обязана накрывать чашу — берег выше уровня прячет излишек под рельефом.
const LAKE_CENTER: Vector2 = Vector2(6, 82)
const LAKE_BASIN_R: float = 16.0
const LAKE_BEACH_R: float = 21.0

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
## Навес площади (canopy) — проходим: под крышей ходят, коллизию дают
## четыре pier_post в его столбах (_plaza_canopies).
const SOLID_TYPES: PackedStringArray = [
	"boulder", "rock_pillar",
	"rock_wall", "ruin_block", "ruin_tower", "ruin_arch", "ruin_column",
	"bench", "log_bridge", "pier_post",
	"plank_deck", "boat",
	"etree_pine", "etree_oak", "etree_aspen", "etree_giant",
	"rrock", "dead_log", "fence",
]
## Предметы раскладки без коллизии (vfx-fix, баг 2): мелкая растительность
## проходима, рама ruin_gate — по задумке (проём закрывает RuinGate).
## Тест проверяет: каждый тип раскладки — либо SOLID (форма в prop_meshes),
## либо здесь; ничего третьего не бывает.
const PASS_THROUGH_TYPES: PackedStringArray = [
	"reed", "pebble", "fern", "ruin_gate", "canopy",
	"etree_bush", "rgrass", "rflower", "riris", "mrock",
]
## ГПСЧ цветочных акцентов у валунов Леса (доработка под эталон): не
## сдвигает основную последовательность rng раскладки.
const STONE_FLOWER_SEED: int = 60409
## ГПСЧ наполнения зон (П5.13, блок 5): кусты, коряги, валуны и деревья
## берега Озера — добавки поверх прежней раскладки, её поток не трогаем.
const FILLER_SEED: int = 20261018


## Полные данные острова (детерминированы): heights (карта высот, м),
## props (предметы: тип, позиция, поворот, масштаб, вариант, тон), tint
## (подсказки цвета рельефа), water, hang, stones, spawn_zones, poi,
## bounds.
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
	_erode(heights)
	_carve_crevasse(heights)
	_bridge_ramps(heights)
	_lookouts(heights)
	_carve_forest_gully(heights)
	# Второй проход выравнивания: запланированные обрывы (каньон, площадки
	# смотровых) защищены, а их кромки получают пологий подход к рельефу.
	_limit_slopes(heights, _protected_cells())
	# Доработка-2 П5.13, П1: лёгкое сглаживание карты высот — эрозия и шум
	# базового рельефа оставляли мелкую рябь шага сетки, читавшуюся на
	# склонах. Один лапласиан 3×3: линейные участки (равномерные склоны
	# холмов) не меняются вовсе, вес гаснет на крутых перепадах — кромки
	# террас, стенки оврага и смотровых (уклон около MAX_STEP) не размываются.
	_smooth_pass(heights)
	var data := {
		"heights": heights,
		"props": [],
		"tint": tint_hints(),
		"water": {
			"sea": {"center": Vector2(0, 0), "size": Vector2(HALF * 2, HALF * 2), "level": SEA_LEVEL},
			# Доработка П5.13: плоскость 34 × 34 накрывает чашу озера
			# (LAKE_BASIN_R с запасом) — берег выше уровня воды прячет излишек
			# под рельефом, видимый контур задаёт береговая линия чаши.
			"lake": {"center": LAKE_CENTER, "size": Vector2(34, 34), "level": SEA_LEVEL},
		},
	}
	var props: Array = data["props"]
	# Точки интереса резервируются до посадки деревьев: на их клетках ничего
	# не вырастает. Камни духа и спавны — на прежних местах кубической версии.
	var stones: Array[Vector3] = []
	var spawns: Dictionary = {}
	var reserved: Dictionary = _points_of_interest(heights, stones, spawns)
	_forest_landmarks(heights, props, reserved)
	_trees_and_rocks(heights, props, rng, reserved)
	_crevasse_walls(props, rng)
	_lookout_walls(props, rng)
	_bridges(props, rng)
	var ruins: Dictionary = _ruins(heights, props, rng)
	var pier: Dictionary = _pier_and_boats(heights, props)
	var fire: Dictionary = _campfire(heights, props)
	_plaza_canopies(props)
	# П5.13, блок 5: деревня у Площади (участки жителей с заборами; дома —
	# доработка убрала срубы-коробки, встанут моделью) и наполнение
	# зон (кусты, коряги, валуны, деревья у Озера) — свои потоки rng:
	# прежняя раскладка не сдвигается, добавки поверх неё. Постройки — до
	# наполнения: якоря наполнения включают их углы (не загораживать подход).
	var village: Dictionary = _village(props)
	_zone_fill(heights, props, reserved, village, ruins, pier, fire,
		stones, spawns)
	var lookouts: Array = []
	for center: Vector2i in LOOKOUTS:
		lookouts.append({
			"center": Vector3(float(center.x), LOOKOUT_TOP_H, float(center.y)),
		})
	data["stones"] = stones
	data["spawn_zones"] = spawns
	data["hang"] = _hang()
	data["poi"] = {
		"ruins": ruins, "pier": pier, "campfire": fire,
		"lookouts": lookouts, "village": village,
	}
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


## Радиус капсулы игрока (player.tscn): боксы коллизий в mechanics_reach
## расширяются на него — клетка считается «на предмете», если персонаж
## в её центре пересекает бокс; тесные щели между заборами деревни
## для капсулы непроходимы.
const PLAYER_R: float = 0.35


## Достижимые клетки с учётом наполнения (П5.13, блок 5): как
## walkable_reach, но верхние поверхности строятся и из боксов коллизий
## твёрдых предметов — «ступени» на их верхнюю грань. Так честно видно,
## что наполнение не отрезает механики: низкое (валун кольца костра,
## гребень стены каньона 0.4 м) персонаж перешагивает автоподъёмом, и BFS
## проходит по верху; высокое (ствол дерева 9 м, забор 1.05 м —
## выше MAX_STEP) становится барьером. Вниз BFS не ограничен — срыв
## с кромки в расщелину возможен всегда (механика 9.1). Рама ruin_gate
## проходима (проём держит узел RuinGate — механика плит, раздел 9.2).
## Возвращает {"cells": посещённые клетки, "tops": клетки, чья высота —
## верх предмета}: в "tops" путь возможен только поверх предмета
## (например, на валун или стену руин), но не сквозь него.
static func mechanics_reach(data: Dictionary) -> Dictionary:
	var heights := _surface_heights(data)
	var tops: Dictionary = {}
	for prop: Dictionary in data["props"]:
		var type := String(prop["type"])
		if type == "plank_deck" or type == "boat" or type == "ruin_gate":
			continue  # настилы уже поверхности, рама ворот проходима
		var size: Vector3 = PropMeshes.collision_size(StringName(type), prop["scale"])
		if size == Vector3.ZERO:
			continue
		var pos: Vector3 = prop["pos"]
		var yaw: float = float(prop["yaw"])
		# Верх коллизии — поверхность клетки, если персонаж в её центре
		# пересекает бокс (полуширины + радиус капсулы); выше берём верх.
		var top: float = pos.y + size.y
		var hx: float = size.x * 0.5 + PLAYER_R
		var hz: float = size.z * 0.5 + PLAYER_R
		var cos_y := cos(yaw)
		var sin_y := sin(yaw)
		var reach_x: float = absf(cos_y) * hx + absf(sin_y) * hz
		var reach_z: float = absf(sin_y) * hx + absf(cos_y) * hz
		for x: int in range(int(floor(pos.x - reach_x)), int(ceil(pos.x + reach_x))):
			for z: int in range(int(floor(pos.z - reach_z)), int(ceil(pos.z + reach_z))):
				var dx: float = float(x) + 0.5 - pos.x
				var dz: float = float(z) + 0.5 - pos.z
				var lx: float = dx * cos_y + dz * sin_y
				var lz: float = -dx * sin_y + dz * cos_y
				if absf(lx) <= hx and absf(lz) <= hz:
					var key := Vector2i(x, z)
					if heights.get(key, -1e9) < top:
						heights[key] = top
						tops[key] = true
	# BFS от спавна площади: шаг не выше MAX_STEP.
	var start := Vector2i(0, 10)
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
	return {"cells": visited, "tops": tops}


## Высота рельефа в точке (м) или NaN за краем карты.
static func top_of(data: Dictionary, x: int, z: int) -> float:
	if absi(x) > HALF or absi(z) > HALF:
		return NAN
	return (data["heights"] as PackedFloat32Array)[_idx(x, z)]


## Высота поверхности рельефа в дробной точке (vfx-fix, баг 3): та же
## триангуляция, что у меша TerrainBuilder (квадрат сетки режется диагональю
## (x,z)–(x+1,z+1)), без округления к ближайшему узлу. Для маршрутов
## зверьков и высот «по земле» в рантайме.
static func ground_height(heights: PackedFloat32Array, fx: float, fz: float) -> float:
	var gx := clampf(fx + HALF, 0.0, POINTS - 2.0)
	var gz := clampf(fz + HALF, 0.0, POINTS - 2.0)
	var x0 := int(gx)
	var z0 := int(gz)
	var u := gx - float(x0)
	var v := gz - float(z0)
	var h00 := heights[z0 * POINTS + x0]
	var h10 := heights[z0 * POINTS + x0 + 1]
	var h01 := heights[(z0 + 1) * POINTS + x0]
	var h11 := heights[(z0 + 1) * POINTS + x0 + 1]
	if u >= v:
		# Треугольник (x,z)–(x+1,z+1)–(x+1,z): подъём по u к (x+1,z), затем по v.
		return h00 + (h10 - h00) * u + (h11 - h10) * v
	# Треугольник (x,z)–(x,z+1)–(x+1,z+1): подъём по v к (x,z+1), затем по u.
	return h00 + (h11 - h01) * u + (h01 - h00) * v


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
		var weight: float = _zone_weight(d, reach)
		mix += colors[i] * weight
		total += weight
	if total <= 0.0:
		return Color.WHITE
	return mix / total


## Сила зонального тона в точке (П5.13, блок 4, планка Ж: бесшовность):
## сумма весов зон с отсечкой в 1. Вне охвата зон 0 — тон отсутствует.
## Смешения умножают свою долю на силу, поэтому к краю охвата зональный
## цвет растворяется в базовый материал плавно: раньше нормализация
## mix/total держала полный тон до самой границы охвата, и на метре
## «зона кончилась» цвет резко терял зональность (шов между зонами —
## находка теста test_zone_blend_is_smooth).
static func zone_color_strength(pos: Vector2) -> float:
	var total: float = 0.0
	for zone: Dictionary in ZONES:
		var reach: float = float(zone["radius"]) * 1.4
		var d: float = pos.distance_to(zone["center"])
		if d >= reach:
			continue
		total += _zone_weight(d, reach)
	return minf(total, 1.0)


## Профиль веса зоны (smoothstep): наклон нулевой в центре зоны и на
## границе охвата — линейный профиль «переламывался» на стыках зон
## видимой ломаной в цвете земли, тумана и тинт предметов.
static func _zone_weight(d: float, reach: float) -> float:
	var t: float = clampf(1.0 - d / reach, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


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
			var d_lake: float = Vector2(x - LAKE_CENTER.x, z - LAKE_CENTER.y).length()
			if d_lake < LAKE_BASIN_R:
				h = -1.2
			elif is_land and d_lake < LAKE_BEACH_R:
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


## Доработка-2 П5.13, П1: сглаживание карты высот одним лапласианом 3×3.
## На линейных участках (равномерный склон) среднее восьми соседей равно
## самой точке — склон не меняется; выравнивается только высокочастотная
## рябь эрозии и базового шума. Вес гаснет по максимальному перепаду
## к соседям, начиная с 0.8 · MAX_STEP: рябь эрозии на склонах (перепады
## заметно ниже лимита) гасится полным весом, у кромок террас и смотровых
## (перепад упирается в MAX_STEP, диагональные — выше) вес почти нулевой —
## запланированные обрывы сохраняются. Рамка карты (край за островом)
## не трогается.
static func _smooth_pass(heights: PackedFloat32Array) -> void:
	var source: PackedFloat32Array = heights.duplicate()
	for z: int in range(-HALF + 1, HALF):
		for x: int in range(-HALF + 1, HALF):
			var here: float = source[_idx(x, z)]
			var sum: float = 0.0
			var steepest: float = 0.0
			for dir: Vector2i in [
				Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
				Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
			]:
				var h: float = source[_idx(x + dir.x, z + dir.y)]
				sum += h
				steepest = maxf(steepest, absf(h - here))
			var weight: float = SMOOTH_STRENGTH * (
				1.0 - smoothstep(MAX_STEP * 0.8, MAX_STEP * 1.05, steepest))
			heights[_idx(x, z)] = lerpf(here, sum / 8.0, weight)


## Клетки с запланированными обрывами: каньон и его кромка, площадки
## смотровых (кольцо стены включительно — перепад ровно 3 м сохраняется).
static func _protected_cells() -> Dictionary:
	var cells: Dictionary = {}
	for x: int in range(CREVASSE_X0 - 3, CREVASSE_X1 + 4):
		for z: int in range(CREVASSE_Z0 - 3, CREVASSE_Z1 + 4):
			if _dist_to_crevasse(x, z) <= CREVASSE_RIM_BAND:
				cells[Vector2i(x, z)] = true
	# Лесной овраг: стенки остаются крутыми (камень по уклону), кромка
	# получает пологий подход выравниванием — как у каньона.
	var gully_reach := GULLY_HALF_LEN + GULLY_HALF_W + GULLY_TAPER + 2.0
	for z: int in range(int(GULLY_MID.y - gully_reach), int(GULLY_MID.y + gully_reach) + 1):
		for x: int in range(int(GULLY_MID.x - gully_reach), int(GULLY_MID.x + gully_reach) + 1):
			if gully_across(x, z) <= GULLY_HALF_W:
				cells[Vector2i(x, z)] = true
	for center: Vector2i in LOOKOUTS:
		for dx: int in range(-2, 3):
			for dz: int in range(-2, 3):
				cells[center + Vector2i(dx, dz)] = true
	return cells


## Расщелина: дно каньона и приподнятая кромка, плавно сливающаяся
## с рельефом. Прорезается после выравнивания — стены каньона вертикальные
## (перепад 5 м на клетку), переправа только по мосткам.
## Гидравлическая эрозия каплями (П5.13, блок 3): овраги и осыпи на
## склонах Холмов и вдоль Расщелины. Детерминирована собственным RNG
## (поток rng раскладки предметов не трогаем — их позиции не меняются).
## Капля идёт вниз по градиенту с инерцией, набирает осадок пропорционально
## крутизне и скорости, откладывает веером при переполнении — у подножий
## получаются осыпи, на склонах древовидные промоины. Маска вырезает
## сектор Леса (его запечённые карты весов и вид П5.9 привязаны к высотам)
## и террасы Площади/Руин/Озера; каньон, мостки, смотровые и лесной овраг
## прорезаются ПОСЛЕ эрозии и переустанавливают высоты точно.
static func _erode(heights: PackedFloat32Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_VALUE + 991
	# Клетки запуска: суша вне маски-запрета с уклоном — эрозия работает
	# на склонах, ровные луга не трогает. Маска размываемости замораживается
	# байтовым массивом на входе: в горячем цикле капли она читается одним
	# индексом (вызов _erodible на каждое касание кисти — минуты), а запрет
	# Леса/террас/мелей от хода прогона не зависит.
	var mask := PackedByteArray()
	mask.resize(POINTS * POINTS)
	var spawns: Array[int] = []
	for z: int in range(-HALF + 2, HALF - 1):
		for x: int in range(-HALF + 2, HALF - 1):
			var i: int = (z + HALF) * POINTS + (x + HALF)
			var h: float = heights[i]
			if not _erodible(x, z, h):
				continue
			mask[i] = 1
			var steep: float = maxf(
				absf(heights[i + 1] - h), absf(heights[i - 1] - h))
			steep = maxf(steep, absf(heights[i + POINTS] - h))
			steep = maxf(steep, absf(heights[i - POINTS] - h))
			if steep >= EROSION_SPAWN_SLOPE:
				spawns.append(i)
	if spawns.is_empty():
		return
	# Кисть отложения/смыва: веса билинейного ядра 5 × 5.
	var brush_off: PackedInt32Array = []
	var brush_w: PackedFloat32Array = []
	for dz: int in range(-EROSION_BRUSH, EROSION_BRUSH + 1):
		for dx: int in range(-EROSION_BRUSH, EROSION_BRUSH + 1):
			var wx: float = 1.0 - absf(float(dx)) / float(EROSION_BRUSH + 1.0)
			var wz: float = 1.0 - absf(float(dz)) / float(EROSION_BRUSH + 1.0)
			var weight: float = wx * wz
			if weight > 0.0:
				brush_off.append(dz * POINTS + dx)
				brush_w.append(weight)
	for droplet: int in EROSION_DROPLETS:
		var i: int = spawns[rng.randi_range(0, spawns.size() - 1)]
		var pos := Vector2(
			float(i % POINTS) - HALF + rng.randf(),
			float(i / POINTS) - HALF + rng.randf())
		var dir := Vector2.ZERO
		var speed: float = 1.0
		var water: float = 1.0
		var sediment: float = 0.0
		for step: int in EROSION_MAX_STEPS:
			var cx: int = int(floorf(pos.x)) + HALF
			var cz: int = int(floorf(pos.y)) + HALF
			var fx: float = pos.x - floorf(pos.x)
			var fz: float = pos.y - floorf(pos.y)
			var i00: int = cz * POINTS + cx
			var h00: float = heights[i00]
			var h10: float = heights[i00 + 1]
			var h01: float = heights[i00 + POINTS]
			var h11: float = heights[i00 + POINTS + 1]
			var gradient := Vector2(
				(h10 - h00) * (1.0 - fz) + (h11 - h01) * fz,
				(h01 - h00) * (1.0 - fx) + (h11 - h10) * fx)
			var height: float = lerpf(
				lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)
			dir = (dir * EROSION_INERTIA - gradient * (1.0 - EROSION_INERTIA))
			if dir.length_squared() < 1e-12:
				break
			dir = dir.normalized()
			var new_pos := pos + dir
			# Дальше только по размываемым клеткам: у кромки маски капля
			# оставляет веер осадка и заканчивает путь. Граница карты —
			# с запасом радиуса кисти (±2), индекс не заворачивает на
			# соседнюю строку.
			var nx: int = int(floorf(new_pos.x)) + HALF
			var nz: int = int(floorf(new_pos.y)) + HALF
			if nx < 3 or nz < 3 or nx >= POINTS - 3 or nz >= POINTS - 3 \
					or not mask[nz * POINTS + nx]:
				_brush(heights, mask, cx, cz, sediment, brush_off, brush_w, false)
				break
			var new_height: float = _bilinear(heights, new_pos)
			var delta: float = new_height - height
			if delta >= 0.0:
				# Подъём в гору: капля теряет способность нести осадок.
				var drop: float = minf(sediment, delta * 0.5)
				_brush(heights, mask, cx, cz, drop, brush_off, brush_w, false)
				sediment -= drop
			var capacity: float = maxf(-delta, 0.0) * speed * water \
				* EROSION_CAPACITY
			if sediment > capacity:
				var deposit: float = (sediment - capacity) * EROSION_DEPOSIT
				_brush(heights, mask, cx, cz, deposit, brush_off, brush_w, false)
				sediment -= deposit
			else:
				var erode: float = minf(
					(capacity - sediment) * EROSION_ERODE, maxf(-delta, 0.0))
				_brush(heights, mask, cx, cz, erode, brush_off, brush_w, true)
				sediment += erode
			speed = sqrt(maxf(0.06, speed * speed + -delta * 9.8 * 0.25))
			water *= 1.0 - EROSION_EVAPORATE
			if water < 0.02:
				_brush(heights, mask, cx, cz, sediment, brush_off, brush_w, false)
				break
			pos = new_pos


## Клетка размываема: вне сектора Леса (запечённые карты весов ForestGround
## привязаны к нынешним высотам — эрозия там ломает вид П5.9), суша
## (мельче SEA_H — кромка воды), вне террас Площади/Руин и котловины Озера
## с пляжем (их высоты заданы _apply_zones и после эрозии не
## переустанавливаются).
static func _erodible(x: int, z: int, h: float) -> bool:
	if x < 0 and z < 0:
		return false
	if h <= SEA_H + 0.1:
		return false
	if Vector2(x, z - 4.0).length() < 20.0:
		return false
	if Vector2(x - 58.0, z + 48.0).length() < 26.0:
		return false
	if Vector2(x - 6.0, z - 82.0).length() < 23.0:
		return false
	return true


## Нанести кистью смыв (sign = true, углубление) или осадок (sign = false,
## поднятие) в клетке: только по клеткам замороженной маски, вес из ядра
## кисти; сумма весов нормируется по размываемой части кисти.
static func _brush(
	heights: PackedFloat32Array, mask: PackedByteArray, cx: int, cz: int,
	amount: float, brush_off: PackedInt32Array, brush_w: PackedFloat32Array,
	sign: bool,
) -> void:
	if amount <= 0.0005:
		return
	var center: int = cz * POINTS + cx
	var total: float = 0.0
	for k: int in brush_off.size():
		if mask[center + brush_off[k]]:
			total += brush_w[k]
	if total <= 0.0:
		return
	var share: float = amount / total
	for k: int in brush_off.size():
		var i: int = center + brush_off[k]
		if mask[i]:
			heights[i] += -share * brush_w[k] if sign \
				else share * brush_w[k]


## Высота в дробной точке (билинейно), для шага капли.
static func _bilinear(heights: PackedFloat32Array, p: Vector2) -> float:
	var cx: int = clampi(int(floorf(p.x)) + HALF, 0, POINTS - 2)
	var cz: int = clampi(int(floorf(p.y)) + HALF, 0, POINTS - 2)
	var fx: float = clampf(p.x - floorf(p.x), 0.0, 1.0)
	var fz: float = clampf(p.y - floorf(p.y), 0.0, 1.0)
	var i: int = cz * POINTS + cx
	return lerpf(
		lerpf(heights[i], heights[i + 1], fx),
		lerpf(heights[i + POINTS], heights[i + POINTS + 1], fx), fz)


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


## Лесной овраг: расстояние точки до оси русла (поперёк), со знаком вдоль
## оси. Пользуются копка, резервация клеток и тесты.
static func gully_across(x: float, z: float) -> float:
	var v := Vector2(x, z) - GULLY_MID
	return absf(v.dot(Vector2(-GULLY_DIR.y, GULLY_DIR.x)))


static func gully_along(x: float, z: float) -> float:
	var v := Vector2(x, z) - GULLY_MID
	return v.dot(GULLY_DIR)


## Прорезка русла: плоское дно в сердцевине, крутые стенки, плавная кромка
## и сужение к концам. Глубина на клетку у стенки больше MAX_STEP — клетки
## русла защищены от выравнивания (_protected_cells), как каньон.
static func _carve_forest_gully(heights: PackedFloat32Array) -> void:
	var reach := GULLY_HALF_LEN + GULLY_HALF_W + GULLY_TAPER + 1.0
	for z: int in range(int(GULLY_MID.y - reach), int(GULLY_MID.y + reach) + 1):
		for x: int in range(int(GULLY_MID.x - reach), int(GULLY_MID.x + reach) + 1):
			if absi(x) > HALF or absi(z) > HALF:
				continue
			var across := gully_across(x, z)
			if across >= GULLY_HALF_W:
				continue
			var taper: float = clampf(
				(GULLY_HALF_LEN - absf(gully_along(x, z))) / GULLY_TAPER, 0.0, 1.0)
			if taper <= 0.0:
				continue
			var depth: float = GULLY_DEPTH * (1.0 - smoothstep(
				GULLY_HALF_W * 0.35, GULLY_HALF_W, across)) * smoothstep(
				0.0, 1.0, taper)
			var i: int = _idx(x, z)
			heights[i] = maxf(SEA_H + 0.6, heights[i] - depth)


## Ориентиры Леса (SPEC 2.5, блок 2 П5.7): поляна с огромным деревом и
## овраг с мостиком из брёвен. Собраны вручную (координаты фиксированы),
## генерация от них детерминирована; rng — свой поток, чтобы правки леса
## не двигали ориентиры, и наоборот. Клетки поляны и русла резервируются:
## на поляне не растут деревья, в русле — только папоротники (_trees_and_rocks).
static func _forest_landmarks(
		heights: PackedFloat32Array, props: Array, reserved: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_VALUE + 57
	for dz: int in range(-GIANT_CLEAR_R, GIANT_CLEAR_R + 1):
		for dx: int in range(-GIANT_CLEAR_R, GIANT_CLEAR_R + 1):
			if Vector2(float(dx), float(dz)).length() <= float(GIANT_CLEAR_R):
				reserved[GIANT_CELL + Vector2i(dx, dz)] = true
	var reach := GULLY_HALF_LEN + GULLY_HALF_W + 1.0
	for z: int in range(int(GULLY_MID.y - reach), int(GULLY_MID.y + reach) + 1):
		for x: int in range(int(GULLY_MID.x - reach), int(GULLY_MID.x + reach) + 1):
			if gully_across(x, z) <= GULLY_HALF_W + 1.0 \
					and absf(gully_along(x, z)) <= GULLY_HALF_LEN:
				reserved[Vector2i(x, z)] = true
	# Гигант лесной поляны (~30 м, П5.9 переделка): дуб-исполин ez-tree
	# (oak_large) — раскидистая крона-ориентир (тон kind "plain" — только
	# вариация яркости); посадка по рельефу с утоплением комля.
	var giant_h: float = ground_height(
		heights, GIANT_CELL.x + 0.5, GIANT_CELL.y + 0.5) - 0.15
	_add_prop(props, rng, &"etree_giant",
		Vector3(GIANT_CELL.x + 0.5, giant_h, GIANT_CELL.y + 0.5),
		rng.randf_range(-0.1, 0.1), Vector3.ONE * rng.randf_range(0.95, 1.05),
		"plain", 1)
	# Мостик из брёвен на тропе: ось вдоль тропы (перпендикуляр русла).
	# Верх брёвен — вровень с высоким берегом (толщина бревна 0.28); подход
	# низкого берега поднимается к настилу рампой (_ramp_banks, подъём
	# меньше MAX_STEP — вход без ступеньки с обеих сторон).
	var trail := Vector2(-0.588, -0.809)
	var span := 2.2  # край настила по тропе
	var deck: float = maxf(
		ground_height(heights, GULLY_MID.x + trail.x * span, GULLY_MID.y + trail.y * span),
		ground_height(heights, GULLY_MID.x - trail.x * span, GULLY_MID.y - trail.y * span))
	_ramp_banks(heights, trail, deck)
	_add_prop(props, rng, &"log_bridge",
		Vector3(GULLY_MID.x, deck - 0.28, GULLY_MID.y),
		atan2(trail.x, trail.y), Vector3.ONE, "plain", 1)


## Рампа подхода к мостику: за каждым краем настила полоса 3 × 2 м
## (поперёк тропы чуть шире мостика) поднимается maxf к уровню настила
## с затуханием на три клетки — у дальнего края сливается с рельефом.
## Клетки русла (across ≤ GULLY_HALF_W) не задеты: полоса начинается
## от края настила, дальше от оси русла.
static func _ramp_banks(
	heights: PackedFloat32Array, trail: Vector2, deck: float
) -> void:
	var across := Vector2(-trail.y, trail.x)
	for side: int in [-1, 1]:
		for k: int in 3:
			var target: float = deck - 0.35 * float(k)
			var center := GULLY_MID + trail * (2.2 + float(k)) * float(side)
			for w: float in [-1.5, -0.75, 0.0, 0.75, 1.5]:
				var p := center + across * w
				var cell := Vector2i(roundi(p.x), roundi(p.y))
				if absi(cell.x) > HALF or absi(cell.y) > HALF:
					continue
				var i: int = _idx(cell.x, cell.y)
				heights[i] = maxf(heights[i], target)


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
## из базовых материалов и зональных тонов по радиусам зон. Публичная, чтобы
## П5.7 красил край Леса тем же цветом, что соседние чанки.
static func tint_hints() -> Dictionary:
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
		# Hills: соседняя клетка от камня духа (-46, 32) — у камня появилась
		# коллизия (vfx-fix), спавн внутри него выталкивал игрока наверх.
		"hills": Vector2i(-45, 33),
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


# --- Деревья, камни, трава, цветы ---

## Предметы по правилам зон (раздел 6): плотность, отступы от POI и троп.
## Позиции и масштабы берёт из rng — детерминированно при фиксированном seed.
static func _trees_and_rocks(
	heights: PackedFloat32Array, props: Array, rng: RandomNumberGenerator,
	reserved: Dictionary,
) -> void:
	var forest := Vector2(-52.0, -52.0)
	var trees: Dictionary = {}
	# Доработка под эталон: цветочные акценты у валунов Леса — клетки
	# крупных глыб (rrock) и камней во мху (mrock) собираются здесь, ирисы
	# и жёлтые цветы сажаются вокруг них после основной раскладки.
	var stone_cells: Array[Vector2i] = []
	var big_stones: Dictionary = {}
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
			# Лес (П5.9, блок 4): внутри радиуса 40 м — процедурные деревья
			# EZ-Tree: хвойные основой, лиственные (дуб, осина) рощами по
			# шуму пород _forest_kind. Подлесок — кусты, редкие валежники
			# и камни; ели — в кольце 40–56 м (переход к лугам).
			if d_forest < 40.0 and grassy:
				if rng.randf() < 0.07 and _no_trees_near(trees, x, z, 2):
					trees[cell] = true
					_prop(props, rng, cell, h, _forest_kind(x, z), "plain",
						_forest_variants(_forest_kind(x, z)), heights)
				elif rng.randf() < 0.022:
					_prop(props, rng, cell, h, "etree_bush", "plain", 5, heights)
				elif rng.randf() < 0.006:
					_prop(props, rng, cell, h, "dead_log", "plain", 1)
				elif rng.randf() < 0.004:
					_prop(props, rng, cell, h, "rrock", "plain", 3)
					stone_cells.append(cell)
					big_stones[cell] = true
			# Редкие деревья вокруг леса (не на площади). П5.8, часть A:
			# кольцо перехода занимает хвойное (крупнее кенниевских елей,
			# отступ шире).
			elif d_forest < 56.0 and Vector2(x, z - 4.0).length() > 20.0 and grassy:
				if rng.randf() < 0.007 and _no_trees_near(trees, x, z, 4):
					trees[cell] = true
					_prop(props, rng, cell, h, "etree_pine", "plain", 5, heights)
			# Площадь (П5.13, блок 1): кромку мощения обрамляют редкие
			# дубы и осины эталонного стиля да камни во мху — площадь
			# не голая тарелка; кольцо 20–27 м, за цветочной кромкой.
			elif Vector2(x, z - 4.0).length() >= 20.0 \
					and Vector2(x, z - 4.0).length() <= 27.0 and grassy:
				if rng.randf() < 0.011 and _no_trees_near(trees, x, z, 5):
					trees[cell] = true
					_prop(props, rng, cell, h, _plaza_tree_kind(x, z), "plain", 5, heights)
				elif rng.randf() < 0.008:
					_prop(props, rng, cell, h, "mrock", "plain", 3)
			# Руины (П5.13, блок 1): ели по периметру террасы — руины
			# смотрятся на фоне леса, а не пустоши; за террасой (24–31 м).
			elif Vector2(x - 58.0, z + 48.0).length() >= 24.5 \
					and Vector2(x - 58.0, z + 48.0).length() <= 31.0 and grassy:
				if rng.randf() < 0.012 and _no_trees_near(trees, x, z, 4):
					trees[cell] = true
					_prop(props, rng, cell, h, "etree_pine", "plain", 5, heights)
			# Холмы: валуны повыше, редкие ели, камни у вершин.
			elif in_hills and h > 4.0:
				if rng.randf() < 0.012:
					_prop(props, rng, cell, h, "boulder", "stone")
				elif h < 13.0 and rng.randf() < 0.006:
					_prop(props, rng, cell, h, "etree_pine", "plain", 5, heights)
				elif h > 16.0 and rng.randf() < 0.02:
					_prop(props, rng, cell, h, "rock_pillar", "stone")
			# Пляж: камешки.
			elif h <= 0.9 and h > -0.2 and rng.randf() < 0.05:
				_prop(props, rng, cell, h, "pebble", "stone")
	# Папоротники (П5.7, блок 2): сплошной ковёр по дну оврага (клетки русла
	# зарезервированы от деревьев — здесь это разрешено) и редкие — по влажным
	# низинам леса, где ForestGround красит влажную землю.
	for z: int in range(-HALF, HALF + 1):
		for x: int in range(-HALF, HALF + 1):
			var cell := Vector2i(x, z)
			var h: float = heights[_idx(x, z)]
			var on_gully: bool = gully_across(x, z) <= GULLY_HALF_W \
				and absf(gully_along(x, z)) <= GULLY_HALF_LEN - 1.0
			if on_gully:
				if h > 0.6 and rng.randf() < 0.35:
					_prop(props, rng, cell, h, "fern", "plain", 1)
			elif not reserved.has(cell) and h > 0.9 and h < 3.4 \
					and Vector2(x + 52.0, z + 52.0).length() < 40.0:
				if rng.randf() < 0.05:
					_prop(props, rng, cell, h, "fern", "plain", 1)
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
			if Vector2(x, z).distance_to(forest) < 40.0:
				# П5.9, блок 3: пучки-островки по шуму — густые кочки, между
				# ними проплешины (не ровный ковёр). Не на тропе и не на
				# гравии Площади (тропа читается землёй); в пятнах — россыпь
				# цветов (жёлтые/фиолетовые/белые) и камни во мху. Клетки
				# Леса не проваливаются в луговую раскладку.
				if _is_grassy_forest(heights, x, z):
					var patch: float = _grass_patch(x, z)
					if patch > 0.05:
						# Доработка 2 (эталон): пятнышко — это островок из 3–6
						# соприкасающихся кочек на клетке, а не одиночный пучок:
						# внутри пятна трава густая, между пятнами — голая земля.
						if rng.randf() < 0.70 * patch:
							var tufts: int = 3
							if rng.randf() < 0.75:
								tufts += 1
							if rng.randf() < 0.5:
								tufts += 1
							if rng.randf() < 0.35:
								tufts += 1
							for i: int in tufts:
								var tuft_scale: float = rng.randf_range(0.85, 1.25)
								_add_prop(
									props, rng, &"rgrass",
									Vector3(
										x + rng.randf_range(-0.45, 0.45), h,
										z + rng.randf_range(-0.45, 0.45)),
									rng.randf_range(0.0, TAU),
									Vector3(
										tuft_scale,
										tuft_scale * rng.randf_range(0.9, 1.15),
										tuft_scale),
									"plain", 3)
						elif rng.randf() < 0.10 * patch:
							_prop(props, rng, cell, h, "rflower", "plain", 3)
					if _moss_patch(x, z) > 0.55 and rng.randf() < 0.06:
						_prop(props, rng, cell, h, "mrock", "plain", 3)
						stone_cells.append(cell)
				continue
			# П5.13, блок 1: луга — та же трава и цветы, что в Лесу
			# (ForestPlants/ForestMat): весь остров в едином стиле.
			if rng.randf() < 0.30:
				_prop(props, rng, cell, h, "rgrass", "plain", 3)
			elif rng.randf() < 0.08:
				_prop(props, rng, cell, h, "rflower", "flower", 3)
	# Цветочные акценты у валунов (доработка под эталон): фиолетовые ирисы
	# и жёлтые цветы жмутся к глыбам подлеска — у крупных rrock по 2–3, у
	# мелких мшистых mrock — реже. Отдельный ГПСЧ: раскладка травы и
	# деревьев не сдвигается, детерминизм тот же.
	var flower_rng := RandomNumberGenerator.new()
	flower_rng.seed = STONE_FLOWER_SEED
	for cell: Vector2i in stone_cells:
		# Крупные глыбы — по пять акцентов, мшистые камешки — пара, но не у
		# каждого: цветы должны собираться у камней, а не рассыпаться ковром
		# (доработка: три акцента при Split 55/45 давали ~1.6 ириса —
		# эталонная «гроздь» у глыбы не собиралась).
		var tries: int = 5 if big_stones.has(cell) else 2
		if not big_stones.has(cell) and flower_rng.randf() > 0.5:
			continue
		var start_angle: float = flower_rng.randf_range(0.0, TAU)
		for t: int in tries:
			var ang: float = start_angle + TAU * float(t) / float(tries) \
				+ flower_rng.randf_range(-0.3, 0.3)
			# Кольцо ужато к камню (0.4–0.95 м): из 5 акцентов в кадр у
			# глыбы попадает гроздь, а не одиночная точка поодаль.
			var ring: float = flower_rng.randf_range(0.4, 0.95)
			var spot := Vector2(
				cell.x + 0.5 + cos(ang) * ring, cell.y + 0.5 + sin(ang) * ring)
			var spot_cell := Vector2i(floori(spot.x), floori(spot.y))
			if reserved.has(spot_cell) or trees.has(spot_cell):
				continue
			var fh: float = heights[_idx(spot_cell.x, spot_cell.y)]
			if fh <= 0.9 or fh >= 16.0 \
					or not _is_grassy_forest(heights, spot_cell.x, spot_cell.y):
				continue
			# Сплит в пользу жёлтых (0.45): в кадре у глыбы ирисы собираются
			# в гроздь и без перевеса, а жёлтая «точка» цвета — самый
			# читаемый акцент эталона.
			var iris: bool = flower_rng.randf() < 0.45
			# Жёлтый цветок у камня крупнее лесного (доработка под эталон):
			# обычные лепестки 0.07 м тонули в кочках и дымке — акцент не
			# читался; 1.8–2.3 даёт «точку» цвета. Ирис выше травы: 1.1–1.4.
			var scale: float = flower_rng.randf_range(1.1, 1.4) \
				if iris else flower_rng.randf_range(1.8, 2.3)
			_add_prop(
				props, flower_rng, &"riris" if iris else &"rflower",
				Vector3(spot.x, fh, spot.y), flower_rng.randf_range(0.0, TAU),
				Vector3(scale, scale * flower_rng.randf_range(0.95, 1.2), scale),
				"plain", 3 if iris else 1)
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
		_prop(props, rng, cell, PLAZA_H, "rflower", "flower", 3)


static func _no_trees_near(trees: Dictionary, x: int, z: int, radius: int) -> bool:
	for dx: int in range(-radius, radius + 1):
		for dz: int in range(-radius, radius + 1):
			if trees.has(Vector2i(x + dx, z + dz)):
				return false
	return true


# --- Пятна травы и мха Леса (П5.9, блок 3) ---

## Шум пятен травы (кочки/проплешины) и мха: фиксированные seed — раскладка
## детерминирована, пятна мха совпадают с покраской земли ForestGround.
const GRASS_PATCH_SEED: int = 9107
const GRASS_PATCH_FREQUENCY: float = 0.055
static var _grass_patch_noise: FastNoiseLite
static var _moss_patch_noise: FastNoiseLite


## Вес пятна травы в точке (0 — проплешина, 1 — гуща). Доработка 2:
## порог снижен — шум FastNoiseLite сгущается около нуля, прежние
## 0.42–0.78 давали жидкие пятна со средним весом ~0.2 (трава занимала
## ~10% земли); 0.30–0.62 дают гущу ~0.5–0.6 при тех же проплешинах.
static func _grass_patch(x: int, z: int) -> float:
	if _grass_patch_noise == null:
		_grass_patch_noise = FastNoiseLite.new()
		_grass_patch_noise.seed = GRASS_PATCH_SEED
		_grass_patch_noise.frequency = GRASS_PATCH_FREQUENCY
	return smoothstep(0.30, 0.62, (_grass_patch_noise.get_noise_2d(x, z) + 1.0) * 0.5)


## Вес пятна мха (тот же шум, что красит мох на земле Леса).
static func _moss_patch(x: int, z: int) -> float:
	if _moss_patch_noise == null:
		_moss_patch_noise = FastNoiseLite.new()
		_moss_patch_noise.seed = ForestGround.MOSS_SEED
		_moss_patch_noise.frequency = ForestGround.MOSS_FREQUENCY
	return smoothstep(0.05, 0.75, (_moss_patch_noise.get_noise_2d(x, z) + 1.0) * 0.5)


## Порода дерева Леса (П5.9, блок 4): хвойные основой (~60 %), лиственные
## рощами — дуб и осина пятнами крупного шума (не вразброс). Выбор по
## координатам клетки, а не rng: поток rng раскладки не меняется.
const FOREST_KIND_SEED: int = 9301
static var _forest_kind_noise: FastNoiseLite

static func _forest_kind(x: int, z: int) -> String:
	if _forest_kind_noise == null:
		_forest_kind_noise = FastNoiseLite.new()
		_forest_kind_noise.seed = FOREST_KIND_SEED
		_forest_kind_noise.frequency = 0.03
	var kind := (_forest_kind_noise.get_noise_2d(x, z) + 1.0) * 0.5
	if kind < 0.60:
		return "etree_pine"
	if kind < 0.85:
		return "etree_oak"
	return "etree_aspen"


## Число вариантов вида дерева (ассеты ez-tree в EzTreeMeshes.ASSETS).
static func _forest_variants(type: String) -> int:
	var list: Array = EzTreeMeshes.ASSETS.get(StringName(type), [])
	return maxi(1, list.size())


## Порода дерева у Площади (П5.13, блок 1): лиственные — дуб рощами,
## осина пятнами (тот же шум, что породы Леса, но сдвинут: свои пятна);
## хвойных у тёплой площади нет. Выбор по координатам — rng не сдвигается.
const PLAZA_TREE_SEED: int = 4507
static var _plaza_tree_noise: FastNoiseLite


static func _plaza_tree_kind(x: int, z: int) -> String:
	if _plaza_tree_noise == null:
		_plaza_tree_noise = FastNoiseLite.new()
		_plaza_tree_noise.seed = PLAZA_TREE_SEED
		_plaza_tree_noise.frequency = 0.05
	var kind := (_plaza_tree_noise.get_noise_2d(x, z) + 1.0) * 0.5
	return "etree_oak" if kind < 0.7 else "etree_aspen"


## Клетка леса пригодна для пучков травы: не тропа/гравий (вес < 0.2 —
## тропа читается землёй), уклон не круче 0.7 (на камне травы нет).
static func _is_grassy_forest(heights: PackedFloat32Array, x: int, z: int) -> bool:
	var on_path: float = maxf(
		ForestGround._path_weight(float(x), float(z)),
		ForestGround._plaza_weight(float(x), float(z)))
	if on_path >= 0.2:
		return false
	var worst := 0.0
	for offset: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
		var h: float = heights[_idx(
			clampi(x + offset.x, -HALF, HALF), clampi(z + offset.y, -HALF, HALF))]
		worst = maxf(worst, absf(h - heights[_idx(x, z)]))
	return worst < 0.7


## Добавить предмет «по клетке»: позиция у точки сетки с лёгким сдвигом,
## случайный поворот и разброс масштаба. Типы с.kind-оттенком получают тон
## зоны (instance-цвет MultiMesh смешивается с вершинными цветами меша).
static func _prop(
	props: Array, rng: RandomNumberGenerator, cell: Vector2i, h: float,
	type: String, kind: String, variants: int = 3,
	heights: PackedFloat32Array = PackedFloat32Array(),
) -> void:
	var scale: float = rng.randf_range(0.8, 1.2)
	var pos := Vector3(
		cell.x + rng.randf_range(-0.3, 0.3), h, cell.y + rng.randf_range(-0.3, 0.3)
	)
	# Деревья стоят на рельефе в фактической точке (джиттер сдвигает с
	# узла сетки — на склоне высота угла клетки отличается до ~0.3 м);
	# корневая часть чуть утоплена, чтобы основание ствола не висело.
	if type.begins_with("etree_") and not heights.is_empty():
		pos.y = ground_height(heights, pos.x, pos.z) \
			- clampf(0.08 * scale, 0.05, 0.2)
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
## точке (zone_blend, с силой зоны — П5.13, блок 4: вне охвата зон тон
## нейтрален, к краю растворяется). kind: leaf — листва/кусты (zone_leaf),
## stone — камни и стены (zone_stone), grass — трава (zone_ground),
## flower — цветок из палитры, plain — без уклона. Уклон умеренный:
## стволы и камни не перекрашиваются целиком.
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
	return tint.lerp(zone_color.lerp(Color.WHITE, 0.5),
		0.5 * zone_color_strength(pos))


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
## грань рельефа проходит на 1.5 м от центра площадки 2 × 2 м. Кольцо
## замкнуто — доработка-2 П5.13 (П2) убрала обходные тропы со ступенями:
## смотровые уступы пешеходом не проходимы, только механики (верёвочная
## лестница с юга по LOOKOUT_TOP_H + LookoutLadder, подсадка с головы).
static func _lookout_walls(props: Array, rng: RandomNumberGenerator) -> void:
	var wall_h: float = LOOKOUT_TOP_H - LOOKOUT_BASE_H + 0.4
	for center: Vector2i in LOOKOUTS:
		for side: int in range(4):
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
	# Трава в щелях и щебень (доработка-2 П4): пучки у внутренней кромки
	# стен и во дворе — руины зарастают; сундук, плиты и проход от ворот
	# свободны. Высота — терраса руин (плоская, RUINS_H).
	var chest := Vector2(58.0, -50.0)
	var plates: Array[Vector2] = [
		Vector2(54.0, -41.0), Vector2(58.0, -41.0), Vector2(62.0, -41.0)]
	for edge: int in 4:
		# Кромки двора: по 6 точек на сторону, ~половина с травой.
		for i: int in 6:
			var t: float = float(i + 0.5) / 6.0
			var x: float = lerpf(float(x0 + 1), float(x1 - 1), t) if edge < 2 \
				else (float(x0 + 1) if edge == 2 else float(x1 - 1))
			var z: float = (float(z0 + 1) if edge == 0 else float(z1 - 1)) \
				if edge < 2 else lerpf(float(z0 + 1), float(z1 - 1), t)
			if edge == 1 and x > 55.0 and x < 61.0:
				continue  # у ворот — проход
			var spot := Vector2(x, z)
			if spot.distance_to(chest) < 2.0 \
					or plates.any(func(p: Vector2) -> bool:
						return spot.distance_to(p) < 1.4):
				continue
			if rng.randf() < 0.55:
				_add_prop(props, rng, &"rgrass",
					Vector3(x, RUINS_H, z), rng.randf_range(0.0, TAU),
					Vector3.ONE * rng.randf_range(0.7, 1.3), "grass")
			elif rng.randf() < 0.4:
				_add_prop(props, rng, &"pebble",
					Vector3(x, RUINS_H, z), rng.randf_range(0.0, TAU),
					Vector3.ONE * rng.randf_range(0.8, 1.6), "plain")
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
	# Швартовочные кнехты на конце причала (П5.13, блок 2): короткие
	# столбики по углам настила — лодки «привязаны», причал читается
	# рабочим, а не декорацией.
	for bollard: Vector2i in [Vector2i(5, 71), Vector2i(6, 71)]:
		_add_prop(props, rng, &"pier_post",
			Vector3(bollard.x + 0.35, deck_h - 0.06, bollard.y + 0.6), 0.0,
			Vector3(0.35, 0.6, 0.35), "plain", 1)
	for boat: Vector2i in [Vector2i(13, 74), Vector2i(-3, 78)]:
		_add_prop(props, rng, &"boat",
			Vector3(boat.x + 1.0, SEA_LEVEL + 0.05, boat.y + 1.0),
			TAU * (0.125 if boat.x > 0 else 0.625), Vector3.ONE, "plain", 1)
	return {
		"deck_end": Vector3(6.0, deck_h + 0.1, 71.5),
		"boats": [Vector3(14.0, SEA_LEVEL + 0.4, 74.5), Vector3(-2.0, SEA_LEVEL + 0.4, 78.5)],
	}


## Костёр на площади: лавки вокруг. Каменное кольцо — модель CC0
## (доработка П5.13: узел Campfire ставит stone_fire_pit с шатром
## поленьев и коллизией очага), процедурные валуны у огня убраны.
## Сидение и огонь-логика — П5; здесь геометрия и позиции (площадь — PLAZA_H).
static func _campfire(heights: PackedFloat32Array, props: Array) -> Dictionary:
	var fire := Vector2i(0, 2)
	var ring_rng := rng_static()
	var benches: Array[Vector3] = []
	for i: int in range(8):
		var angle: float = TAU * i / 8.0 + PI / 8.0
		var bench := Vector2(fire) + Vector2(cos(angle), sin(angle)) * 4.5
		# Лавка лицом к костру (модель смотрит в +Z).
		var yaw: float = atan2(-cos(angle), -sin(angle))
		_add_prop(props, ring_rng, &"bench",
			Vector3(bench.x, PLAZA_H, bench.y), yaw, Vector3.ONE, "plain", 1)
		benches.append(Vector3(bench.x, PLAZA_H + 0.45, bench.y))
	return {
		"center": Vector3(0.5, PLAZA_H, 2.5),
		"benches": benches,
	}


## Навесы площади (П5.13, блок 1): два дощатых навеса на столбах южнее
## костра — укрытие от непогоды и силуэт площади. Крыша (canopy) проходима,
## под ней ходят; коллизию дают четыре pier_post, спрятанных в столбах
## меша (радиус меньше видимого столба, вершина заподлицо с прогонами).
## Кольцо 13–14 м от центра: не задевает костёр, лавки, цветочную кромку
## и южный проход к озеру между навесами.
static func _plaza_canopies(props: Array) -> void:
	var rng := rng_static()
	var spots: Array[Vector3] = [
		Vector3(-10.5, PLAZA_H, -8.5),
		Vector3(11.5, PLAZA_H, -7.0),
	]
	var yaws: Array[float] = [0.35, -0.5]
	for i: int in spots.size():
		_add_prop(props, rng, &"canopy", spots[i], yaws[i],
			Vector3.ONE, "plain", 2)
		for x_at: float in [-1.5, 1.5]:
			for z_at: float in [-0.95, 0.95]:
				var local := Vector3(x_at, 0.0, z_at).rotated(Vector3.UP, yaws[i])
				_add_prop(props, rng, &"pier_post", spots[i] + local, 0.0,
					Vector3(0.3, 2.16, 0.3), "plain", 1)


## Деревня у Площади (П5.13, блок 5; доработка — домики-срубы убраны):
## три участка жителей в «карманах» кромки террасы — посередине между
## соседними выходами с площади, так что ни один радиальный путь (Озеро,
## Расщелина, Руины, Холмы, Лес) не перекрывается. Процедурные серые
## коробки-срубы удалены по приёмке: дома жителей встанут готовой
## моделью (сруб Kless, очередь владельца). Крылья заборных секций и
## якоря-углы участков остаются: палисадники раскрыты к площади, вход
## между крыльями свободен, наполнение не ставит предметы вплотную.
## rng_static: правки леса не двигают деревню.
static func _village(props: Array) -> Dictionary:
	var rng := rng_static()
	var plaza: Vector2 = ZONES[0]["center"]
	# Единичные направления выходов с площади (по зонам) и карманы между
	# соседними: юго-восток (Озеро/Расщелина), запад (Холмы/Лес), север
	# (Лес/Руины). Участки на r = 17: терраса (r < 18) плоская.
	var exits: Array[Vector2] = [
		Vector2(0.077, 0.997), Vector2(0.755, 0.646),
		Vector2(0.745, -0.667), Vector2(-0.837, 0.548),
		Vector2(-0.680, -0.733),
	]
	var pockets: Array[int] = [0, 3, 4]
	var anchors: Array[Vector3] = []
	var spots: Array[Vector3] = []
	for pocket: int in pockets:
		var dir: Vector2 = (exits[pocket] + exits[(pocket + 1) % exits.size()]).normalized()
		var pos2d: Vector2 = plaza + dir * 17.0
		var base := Vector3(pos2d.x, PLAZA_H, pos2d.y)
		spots.append(base)
		var yaw: float = atan2(-dir.x, -dir.y)
		# Крылья забора: по две секции вдоль фасада участка (локальный X)
		# с каждой стороны, чуть впереди фасада. Габарит дома по X ±2 —
		# крыло продолжается от угла наружу, проход шириной 2.3 м.
		for side: float in [-1.0, 1.0]:
			for seg: int in 2:
				var local := Vector3(side * (1.15 + seg * 1.9), 0.0, 1.35) \
					.rotated(Vector3.UP, yaw)
				_add_prop(props, rng, &"fence", base + local, yaw,
					Vector3.ONE, "plain", 2)
		# Якоря-углы участка (габарит дома 4.1 × 3.0): наполнение держит
		# отступ — место под будущий дом не зарастает.
		for x_at: float in [-2.05, 2.05]:
			for z_at: float in [-1.5, 1.5]:
				anchors.append(base + Vector3(x_at, 0.0, z_at).rotated(Vector3.UP, yaw))
	return {"anchors": anchors, "spots": spots}


## Наполнение зон (П5.13, блок 5): кусты, коряги, валуны и деревья берега
## Озера на лугах между зонами — весь остров в стиле Леса, без пустошей.
## Свой поток rng (FILLER_SEED): прежняя раскладка не сдвигается. Твёрдые
## предметы держат отступ от якорей механик (спавны, камни духа, плиты,
## сундук, кромка причала, HangPoint, смотровые) и от построек деревни —
## пути и соло-пути не загораживаются; достижимость проверяет тест
## проходимости (test_walkability).
static func _zone_fill(
	heights: PackedFloat32Array, props: Array, reserved: Dictionary,
	village: Dictionary, ruins: Dictionary, pier: Dictionary, fire: Dictionary,
	stones: Array[Vector3], spawns: Dictionary,
) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = FILLER_SEED
	var anchors: Array[Vector3] = []
	anchors.append_array(reserved_anchor_spots(ruins, pier, fire))
	anchors.append_array(stones)
	for zone_name: String in spawns:
		anchors.append(spawns[zone_name])
	anchors.append_array(village["anchors"])
	var trees: Dictionary = {}
	for z: int in range(-HALF, HALF + 1):
		for x: int in range(-HALF, HALF + 1):
			var cell := Vector2i(x, z)
			if reserved.has(cell):
				continue
			var h: float = heights[_idx(x, z)]
			if h <= 0.9 or h > 15.0:
				continue
			var pos := Vector2(x, z)
			var d_plaza: float = pos.distance_to(Vector2(0, 4))
			var d_forest: float = pos.distance_to(Vector2(-52, -52))
			var d_ruins: float = pos.distance_to(Vector2(58, -48))
			var d_lake: float = pos.distance_to(Vector2(6, 82))
			# Двор руин: коряги среди обломков (терраса ровная — SOLID
			# низкий, обход всегда есть).
			if d_ruins < 22.0:
				if rng.randf() < 0.006 and _clear_of_anchors(Vector3(x, h, z), anchors, 2.5):
					_prop(props, rng, cell, h, "dead_log", "plain", 2)
				continue
			# Внутри площади и террасы руин наполнения нет.
			if d_plaza < 21.0 or d_ruins < 26.0:
				continue
			# Каньон расщелины и подходы к мосткам — свободны.
			if x >= CREVASSE_X0 - 2 and x <= CREVASSE_X1 + 2 \
					and z >= CREVASSE_Z0 - 2 and z <= CREVASSE_Z1 + 2:
				continue
			# Полоса причала Озера (подход по берегу) — свободна.
			if x >= 2 and x <= 9 and z >= 56 and z <= 75:
				continue
			# Луга: кусты, коряги, валуны и камни во мху — редко, островки.
			if d_forest >= 42.0 and d_lake > 21.0:
				if rng.randf() < 0.004:
					_prop(props, rng, cell, h, "etree_bush", "plain", 5, heights)
				elif rng.randf() < 0.0015 \
						and _clear_of_anchors(Vector3(x, h, z), anchors, 3.0):
					_prop(props, rng, cell, h, "dead_log", "plain", 2)
				elif rng.randf() < 0.0015 \
						and _clear_of_anchors(Vector3(x, h, z), anchors, 3.0):
					_prop(props, rng, cell, h, "boulder", "stone")
				elif rng.randf() < 0.003:
					_prop(props, rng, cell, h, "mrock", "plain", 3)
				continue
			# Берег Озера (кроме полосы причала): деревья кольцом за
			# камышами, коряги и валуны у кромки — берег живой.
			if d_lake <= 26.0:
				if rng.randf() < 0.01 and _no_trees_near(trees, x, z, 3):
					trees[cell] = true
					_prop(props, rng, cell, h, _forest_kind(x, z), "plain",
						_forest_variants(_forest_kind(x, z)), heights)
				elif rng.randf() < 0.008 \
						and _clear_of_anchors(Vector3(x, h, z), anchors, 3.0):
					_prop(props, rng, cell, h, "dead_log", "plain", 2)
				elif rng.randf() < 0.006:
					_prop(props, rng, cell, h, "mrock", "plain", 3)
				continue
			# Холмы ниже вершин: кусты и коряги в траве.
			if Vector2(x + 58.0, z - 42.0).length() < 42.0 and h < 10.0:
				if rng.randf() < 0.003:
					_prop(props, rng, cell, h, "etree_bush", "plain", 5, heights)
				elif rng.randf() < 0.0015 \
						and _clear_of_anchors(Vector3(x, h, z), anchors, 3.0):
					_prop(props, rng, cell, h, "dead_log", "plain", 2)


## Клетки, возле которых наполнение не ставит твёрдые предметы: спавны и
## камни духа — по спискам из poi, плиты/сундук/ворота руин, конец причала,
## костёр и лавки, смотровые площадки (лестницы и входы троп), HangPoint
## расщелины. Возвращает 3D-точки для дистанционной проверки.
static func reserved_anchor_spots(
	ruins: Dictionary, pier: Dictionary, fire: Dictionary,
) -> Array[Vector3]:
	var spots: Array[Vector3] = []
	spots.append_array(fire["benches"])
	spots.append(fire["center"])
	spots.append(ruins["chest"])
	spots.append(ruins["gate_center"])
	spots.append_array(ruins["plates"])
	spots.append(pier["deck_end"])
	for center: Vector2i in LOOKOUTS:
		spots.append(Vector3(float(center.x), LOOKOUT_TOP_H, float(center.y)))
	for point: Vector3 in _hang()["points"]:
		spots.append(point)
	return spots


## Свободен ли отступ от якорей (твёрдое наполнение не загораживает
## механики и постройки).
static func _clear_of_anchors(pos: Vector3, anchors: Array[Vector3], min_d: float) -> bool:
	for anchor: Vector3 in anchors:
		if Vector2(pos.x, pos.z).distance_to(Vector2(anchor.x, anchor.z)) < min_d:
			return false
	return true


## Детерминированный ГПСЧ для «строительных» предметов без внешнего rng
## (пирс, костёр): свой поток чисел, чтобы правки леса не двигали пирс.
static func rng_static() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_VALUE + 17
	return rng


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
