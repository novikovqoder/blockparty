# Раскладка района (постапокалипсис) — чистые данные по согласованной карте
# (10.11.2026): участок 200×200 м, центр (0, 0), север — −Z, восток — +X,
# 1 ед. = 1 м. Здесь же вопросы «что под ногами»: покрытие точки, глубина
# озера, высота земли — ими пользуются земля, трава и деревья.
class_name DistrictLayout
extends RefCounted

enum Surface { GRASS, ASPHALT, YARD, PATH, WATER, BUILDING }

## Половина стороны участка, м.
const HALF: float = 100.0
## Точка старта игрока (метка 7 на карте, у причала).
const START: Vector3 = Vector3(-7.2, 0.3, 57.6)
## Уровень воды озера и наибольшая глубина, м.
const WATER_LEVEL: float = -0.25
const LAKE_MAX_DEPTH: float = 2.6
## На каком расстоянии от берега дно выходит на полную глубину, м.
const LAKE_SLOPE_M: float = 9.0

## Пятиэтажки: имя, X, Z, длина, глубина, поворот (град), число подъездов.
## Локально подъезды смотрят в +Z; поворот ставит их во двор.
const HOUSES: Array = [
	["HouseNorth", 12.4, -72.9, 56.5, 13.4, 0.0, 4],
	["HouseWest", -21.5, -44.7, 44.5, 12.0, 90.0, 3],
	["HouseEast", 44.2, -41.9, 49.1, 11.5, -90.0, 3],
	["HouseFar", 73.4, -34.4, 49.0, 12.0, -90.0, 3],
]
## Открытый подъезд (решение владельца): северный дом, второй с запада.
const OPEN_HOUSE: String = "HouseNorth"
const OPEN_ENTRANCE: int = 1
## Руины на юго-востоке (закрыты): имя, X, Z, длина, глубина, поворот, этажей.
const RUINS: Array = [
	["RuinA", 65.1, 47.5, 17.5, 13.6, -15.0, 2],
	["RuinB", 79.4, 53.9, 13.6, 15.9, -15.0, 2],
	["RuinC", 69.1, 35.6, 36.7, 7.2, -15.0, 1],
]
## Малые постройки: имя, X, Z, ширина, глубина, высота, поворот, вид.
const BUILDINGS: Array = [
	["Shop", -15.0, 22.6, 14.4, 11.5, 4.0, 180.0, "shop"],
	["Transformer", -13.1, -16.3, 4.8, 4.8, 3.0, 90.0, "brick"],
	["YardShed", 21.2, -48.6, 4.8, 4.8, 2.5, 180.0, "brick"],
	["YardBox", 21.2, -21.4, 5.6, 4.0, 2.5, 0.0, "brick"],
	["GarageExtra", -37.3, -7.0, 8.0, 4.8, 2.8, -90.0, "garage"],
]
## Ряд гаражей вдоль X, воротами на площадку (+Z).
const GARAGE_COUNT: int = 8
const GARAGE_X0: float = -90.4
const GARAGE_X1: float = -39.4
const GARAGE_Z: float = -19.5
const GARAGE_DEPTH: float = 6.5
## Блоки-заглушки и завалы: имя, X, Z, размер X, размер Z, высота, поворот, вид.
const BLOCKS: Array = [
	["Bus", 25.5, 6.1, 12.0, 3.0, 2.55, -21.0, "rust"],
	["TruckA", -9.1, 0.8, 6.5, 2.4, 2.6, -5.0, "rust"],
	["TruckB", -33.0, 13.6, 6.0, 2.4, 2.6, 85.0, "rust"],
	["Pier", -27.3, 64.6, 19.0, 4.5, 0.45, 19.7, "wood"],
	["BarricadeWestA", -95.5, 3.0, 2.6, 0.7, 0.9, 20.0, "concrete"],
	["BarricadeWestB", -95.0, 6.4, 2.6, 0.7, 0.9, -12.0, "concrete"],
	["BarricadeWestC", -95.6, 9.6, 2.6, 0.7, 0.9, 8.0, "concrete"],
	["BarricadeEastA", 95.3, 18.0, 2.6, 0.7, 0.9, -70.0, "concrete"],
	["BarricadeEastB", 95.8, 21.2, 2.6, 0.7, 0.9, -95.0, "concrete"],
	["BarricadeEastC", 95.2, 24.4, 2.6, 0.7, 0.9, -80.0, "concrete"],
	["RuinFenceNorth", 66.0, 29.5, 46.0, 0.25, 2.2, -15.0, "concrete"],
	["RuinFenceWest", 46.5, 46.0, 0.25, 30.0, 2.2, -15.0, "concrete"],
]
## Легковые машины (под тентом): X, Z, поворот.
const CARS: Array = [
	[-92.3, 9.6, 0.0], [-55.3, 7.7, -10.0], [-71.6, 18.0, 5.0],
	[-14.7, 6.5, 0.0], [12.4, 19.6, -50.0], [42.4, 22.0, -8.0],
	[71.1, 11.6, -15.0], [66.7, 21.5, -10.0], [-4.3, 39.6, 70.0],
	[-4.3, 27.1, 20.0], [75.4, 65.9, -15.0], [78.3, 70.3, -10.0],
]
## Полосы покрытия: начало X/Z, конец X/Z, ширина, покрытие.
const STRIPS: Array = [
	[-100.0, 6.1, 11.6, 6.1, 11.2, Surface.ASPHALT],
	[11.6, 6.1, 100.0, 22.0, 11.2, Surface.ASPHALT],
	[8.5, 2.1, 8.5, -17.1, 7.0, Surface.ASPHALT],
	[-10.7, 28.4, -6.7, 57.9, 3.0, Surface.PATH],
]
## Площадки: X, Z, размер X, размер Z, покрытие.
const PADS: Array = [
	[-62.5, -6.9, 46.3, 14.0, Surface.ASPHALT],
	[13.2, -38.6, 35.1, 43.1, Surface.YARD],
]
## Берег озера (метка 6): многоугольник X/Z; южная и западная стороны —
## граница участка.
const LAKE: Array[Vector2] = [
	Vector2(-100.0, 53.9), Vector2(-85.6, 43.5), Vector2(-68.1, 39.1),
	Vector2(-52.2, 41.1), Vector2(-39.4, 49.1), Vector2(-28.2, 55.5),
	Vector2(-17.1, 61.4), Vector2(-7.5, 71.5), Vector2(-3.5, 84.0),
	Vector2(-2.5, 100.0), Vector2(-100.0, 100.0),
]
## Башня Главного Компьютера (метка 8): на северо-востоке, за дымкой.
const TOWER_POS: Vector3 = Vector3(300.0, 0.0, -300.0)
const TOWER_HEIGHT: float = 260.0

static var _lake: PackedVector2Array = PackedVector2Array()
static var _footprints: Array[Dictionary] = []


static func lake_polygon() -> PackedVector2Array:
	if _lake.is_empty():
		_lake = PackedVector2Array(LAKE)
	return _lake


static func in_lake(p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, lake_polygon())


## Глубина дна под точкой, м (0 — вне озера): плавно от берега.
static func lake_depth(p: Vector2) -> float:
	if not in_lake(p):
		return 0.0
	var poly: PackedVector2Array = lake_polygon()
	var best: float = INF
	for i: int in poly.size():
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(
			p, poly[i], poly[(i + 1) % poly.size()])
		best = minf(best, p.distance_to(closest))
	return LAKE_MAX_DEPTH * smoothstep(0.0, LAKE_SLOPE_M, best)


static func ground_height(p: Vector2) -> float:
	return -lake_depth(p)


## Пятна построек: {center, half, yaw} — дома, руины, малые постройки, гаражи.
static func footprints() -> Array[Dictionary]:
	if not _footprints.is_empty():
		return _footprints
	for house: Array in HOUSES + RUINS:
		_footprints.append({
			"center": Vector2(house[1], house[2]),
			"half": Vector2(house[3], house[4]) * 0.5,
			"yaw": deg_to_rad(float(house[5])),
		})
	for b: Array in BUILDINGS:
		_footprints.append({
			"center": Vector2(b[1], b[2]), "half": Vector2(b[3], b[4]) * 0.5,
			"yaw": deg_to_rad(float(b[6])),
		})
	for b: Array in BLOCKS:
		if String(b[0]) == "Pier":
			continue
		_footprints.append({
			"center": Vector2(b[1], b[2]), "half": Vector2(b[3], b[4]) * 0.5,
			"yaw": deg_to_rad(float(b[6])),
		})
	_footprints.append({
		"center": Vector2((GARAGE_X0 + GARAGE_X1) * 0.5, GARAGE_Z),
		"half": Vector2((GARAGE_X1 - GARAGE_X0) * 0.5, GARAGE_DEPTH * 0.5),
		"yaw": 0.0,
	})
	return _footprints


## Точка внутри пятна постройки (с запасом margin, м).
static func in_footprint(p: Vector2, margin: float = 0.0) -> bool:
	for fp: Dictionary in footprints():
		var d: Vector2 = p - (fp["center"] as Vector2)
		# Обратный поворот rotate_y(yaw): X' = x cos − z sin, Z' = x sin + z cos.
		var yaw: float = fp["yaw"]
		var local := Vector2(
			d.x * cos(yaw) - d.y * sin(yaw), d.x * sin(yaw) + d.y * cos(yaw))
		var half: Vector2 = fp["half"]
		if absf(local.x) <= half.x + margin and absf(local.y) <= half.y + margin:
			return true
	return false


## Покрытие под точкой.
static func surface_at(p: Vector2) -> int:
	if in_lake(p):
		return Surface.WATER
	if in_footprint(p, 0.3):
		return Surface.BUILDING
	for strip: Array in STRIPS:
		var a := Vector2(strip[0], strip[1])
		var b := Vector2(strip[2], strip[3])
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(p, a, b)
		if p.distance_to(closest) <= float(strip[4]) * 0.5:
			return int(strip[5])
	for pad: Array in PADS:
		if absf(p.x - float(pad[0])) <= float(pad[2]) * 0.5 \
				and absf(p.y - float(pad[1])) <= float(pad[3]) * 0.5:
			return int(pad[4])
	return Surface.GRASS
