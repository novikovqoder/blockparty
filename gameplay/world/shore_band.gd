# П15 9.3: карта расстояния до береговой линии (SDF), запечённая из карты
# высот острова. Знаковое поле: суша > 0, вода < 0, метры; текстура
# RF 257 × 257 (узлы карты высот, 1 узел = 1 м), uv = (world.xz + 128)/256 —
# та же схема, что height_tex кольца П14. Пена, накат и отлив строятся
# по этому расстоянию, искажённому шумом, а не по толщине из буфера
# глубины: линия пены — плавная кривая, не рёбра треугольников земли.
# Печать — двухпроходный 8SSEDT с субпиксельными источниками (точки
# пересечения уровня по рёбрам узлов): узлы, инцидентные контуру,
# инициализируются точным расстоянием до точки пересечения, остальное
# распространяется проходами; вычисляется полоса у берега (дальше пена,
# накат и полоса берега не живут), прочее — clamp SDF_RANGE.
class_name ShoreBand
extends RefCounted

const ART: IslandArt = preload("res://gameplay/world/island_art.res")

## Дальность SDF, м: дальше берега не интересует (пена ≤ 0.3 м, накат
## ≤ 0.4, полоса берега ±1 м) — вне полосы поле зажимается в ±SDF_RANGE.
const SDF_RANGE: float = 5.0
## Запас маски вычисления, узлы: 8SSEDT-путь узла с точным SDF d короче
## d узлов связности, маска радиуса SDF_RANGE + 2 покрывает все такие
## пути — значения в интересной полосе точны.
const MASK_GROW: int = 7

const INF: float = 1e9

## Кэш печёной карты (остров и уровень воды одни на процесс).
static var _sdf_cache: Image = null


## Карта SDF для уровня воды level (море и озеро на одном уровне —
## карта одна). Возвращает Image RF POINTS × POINTS.
static func sdf_image(art: IslandArt, level: float) -> Image:
	if _sdf_cache != null:
		return _sdf_cache
	var heights: PackedFloat32Array = art.heights
	var n: int = IslandGen.POINTS
	var count: int = n * n
	var is_water := PackedByteArray()
	is_water.resize(count)
	for i: int in count:
		is_water[i] = 1 if heights[i] < level else 0
	# Два поля 8SSEDT: у суши — расстояние до воды (d_in), у воды — до
	# суши (d_out); sdf = d_in − d_out. Точки-источники (px, py) несут
	# субпиксельные координаты пересечения уровня.
	var d_in := PackedFloat32Array()
	var d_out := PackedFloat32Array()
	var px_in := PackedFloat32Array()
	var py_in := PackedFloat32Array()
	var px_out := PackedFloat32Array()
	var py_out := PackedFloat32Array()
	d_in.resize(count)
	d_out.resize(count)
	px_in.resize(count)
	py_in.resize(count)
	px_out.resize(count)
	py_out.resize(count)
	for i: int in count:
		d_in[i] = INF
		d_out[i] = INF
	# Источники: пересечения уровня по рёбрам узлов; обоим концам ребра
	# — кандидат (точное расстояние до контура).
	for z: int in n:
		var row: int = z * n
		for x: int in n:
			var h0: float = heights[row + x]
			if x + 1 < n:
				var h1: float = heights[row + x + 1]
				if (h0 < level) != (h1 < level):
					var t: float = (level - h0) / (h1 - h0)
					_seed_node(d_in, d_out, px_in, py_in, px_out, py_out,
						is_water, row + x, float(x) + t, float(z))
					_seed_node(d_in, d_out, px_in, py_in, px_out, py_out,
						is_water, row + x + 1, float(x) + t, float(z))
			if z + 1 < n:
				var h2: float = heights[row + n + x]
				if (h0 < level) != (h2 < level):
					var t: float = (level - h0) / (h2 - h0)
					_seed_node(d_in, d_out, px_in, py_in, px_out, py_out,
						is_water, row + x, float(x), float(z) + t)
					_seed_node(d_in, d_out, px_in, py_in, px_out, py_out,
						is_water, row + n + x, float(x), float(z) + t)
	# Маска полосы вычисления: dilate от узлов-источников MASK_GROW шагов.
	var mask := PackedByteArray()
	mask.resize(count)
	var front: Array[int] = []
	for i: int in count:
		if d_in[i] < INF or d_out[i] < INF:
			mask[i] = 1
			front.append(i)
	for _grow: int in MASK_GROW:
		var next_front: Array[int] = []
		for i: int in front:
			var x: int = i % n
			var z: int = i / n
			for d: int in 8:
				var nx: int = x + DX8[d]
				var nz: int = z + DZ8[d]
				if nx < 0 or nx >= n or nz < 0 or nz >= n:
					continue
				var j: int = nz * n + nx
				if mask[j] == 0:
					mask[j] = 1
					next_front.append(j)
		front = next_front
	# 8SSEDT: проход вниз-вправо и вверх-влево, релаксация точками
	# соседей (евклидово расстояние до их источника).
	for pass_index: int in 2:
		var forward: bool = pass_index == 0
		var z_from: int = 0 if forward else n - 1
		var z_to: int = n if forward else -1
		var z_step: int = 1 if forward else -1
		var z: int = z_from
		while z != z_to:
			var x_from: int = 0 if forward else n - 1
			var x_to: int = n if forward else -1
			var x_step: int = 1 if forward else -1
			var x: int = x_from
			while x != x_to:
				var i: int = z * n + x
				if mask[i] == 1:
					# Соседи, уже посчитанные в этом направлении.
					for d: int in 4:
						var nx: int = x + (DX8[d] if forward else -DX8[d])
						var nz: int = z + (DZ8[d] if forward else -DZ8[d])
						if nx < 0 or nx >= n or nz < 0 or nz >= n:
							continue
						var j: int = nz * n + nx
						if mask[j] == 0 or is_water[j] != is_water[i]:
							continue
						if is_water[i] == 1:
							_relax(d_out, px_out, py_out, i, j,
								float(x), float(z))
						else:
							_relax(d_in, px_in, py_in, i, j,
								float(x), float(z))
				x += x_step
			z += z_step
	# Сборка знакового поля, clamp в ±SDF_RANGE.
	var sdf := PackedFloat32Array()
	sdf.resize(count)
	for i: int in count:
		var d: float = d_out[i] if is_water[i] == 1 else d_in[i]
		var dist: float = clampf(d if d < INF else SDF_RANGE, 0.0, SDF_RANGE)
		sdf[i] = -dist if is_water[i] == 1 else dist
	var image := Image.create_from_data(n, n, false, Image.FORMAT_RF,
		sdf.to_byte_array())
	_sdf_cache = image
	return image


## Текстура SDF (создаётся один раз; линейная фильтрация сглаживает
## изолинии — линия пены плавная).
static func sdf_texture(art: IslandArt, level: float) -> ImageTexture:
	return ImageTexture.create_from_image(sdf_image(art, level))


## Соседи 8-связности (первые 4 — «назад» для прохода вперёд:
## лево, верх и обе верхние диагонали; остальные — для dilate маски).
const DX8: Array[int] = [-1, 0, -1, 1, -1, 1, 0, 1]
const DZ8: Array[int] = [0, -1, -1, -1, 1, 0, 1, 1]


## Инициализация узла точкой контура (точное расстояние, сторона поля —
## по знаку узла).
static func _seed_node(
	d_in: PackedFloat32Array, d_out: PackedFloat32Array,
	px_in: PackedFloat32Array, py_in: PackedFloat32Array,
	px_out: PackedFloat32Array, py_out: PackedFloat32Array,
	is_water: PackedByteArray, index: int, pt_x: float, pt_z: float,
) -> void:
	var x: float = float(index % IslandGen.POINTS)
	var z: float = float(index / IslandGen.POINTS)
	var d: float = Vector2(x - pt_x, z - pt_z).length()
	if is_water[index] == 1:
		if d < d_out[index]:
			d_out[index] = d
			px_out[index] = pt_x
			py_out[index] = pt_z
	else:
		if d < d_in[index]:
			d_in[index] = d
			px_in[index] = pt_x
			py_in[index] = pt_z


## Релаксация: источник соседа j может быть ближе к узлу i.
static func _relax(
	d: PackedFloat32Array, px: PackedFloat32Array, py: PackedFloat32Array,
	i: int, j: int, x: float, z: float,
) -> void:
	if d[j] >= INF:
		return
	var cand: float = Vector2(x - px[j], z - py[j]).length()
	if cand < d[i]:
		d[i] = cand
		px[i] = px[j]
		py[i] = py[j]


## Выборка SDF в мировых координатах (билинейно, для тестов и отладки):
## суша > 0, вода < 0, метры.
static func sdf_at(image: Image, wx: float, wz: float) -> float:
	var n: int = image.get_width()
	var fx: float = clampf(wx + IslandGen.HALF, 0.0, float(n - 1))
	var fz: float = clampf(wz + IslandGen.HALF, 0.0, float(n - 1))
	var x0: int = clampi(int(fx), 0, n - 2)
	var z0: int = clampi(int(fz), 0, n - 2)
	var tx: float = fx - float(x0)
	var tz: float = fz - float(z0)
	var h00: float = image.get_pixel(x0, z0).r
	var h10: float = image.get_pixel(x0 + 1, z0).r
	var h01: float = image.get_pixel(x0, z0 + 1).r
	var h11: float = image.get_pixel(x0 + 1, z0 + 1).r
	return lerpf(
		lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## Точки пересечения уровня с рёбрами узлов (мировые координаты) — для
## честной проверки SDF в тестах: расстояние до ближайшей точки контура.
static func contour_points(
	heights: PackedFloat32Array, level: float,
) -> PackedVector2Array:
	var n: int = IslandGen.POINTS
	var points := PackedVector2Array()
	for z: int in n:
		var row: int = z * n
		for x: int in n:
			var h0: float = heights[row + x]
			if x + 1 < n:
				var h1: float = heights[row + x + 1]
				if (h0 < level) != (h1 < level):
					var t: float = (level - h0) / (h1 - h0)
					points.append(Vector2(
						float(x) + t - IslandGen.HALF,
						float(z) - IslandGen.HALF))
			if z + 1 < n:
				var h2: float = heights[row + n + x]
				if (h0 < level) != (h2 < level):
					var t: float = (level - h0) / (h2 - h0)
					points.append(Vector2(
						float(x) - IslandGen.HALF,
						float(z) + t - IslandGen.HALF))
	return points


## Честное расстояние от точки до контура (перебор точек пересечения),
## со знаком узла: суша > 0, вода < 0.
static func true_distance(
	heights: PackedFloat32Array, level: float,
	contour: PackedVector2Array, wx: float, wz: float,
) -> float:
	var n: int = IslandGen.POINTS
	var node: int = clampi(int(roundf(wz)) + IslandGen.HALF, 0, n - 1) * n \
		+ clampi(int(roundf(wx)) + IslandGen.HALF, 0, n - 1)
	var sign: float = 1.0 if heights[node] >= level else -1.0
	var best: float = INF
	for point: Vector2 in contour:
		best = minf(best, point.distance_to(Vector2(wx, wz)))
	return best * sign
