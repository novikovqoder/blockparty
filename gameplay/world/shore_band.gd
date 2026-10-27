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

## П15 9.1: шаг сетки береговой полосы, м.
const BAND_STEP: float = 0.25
## Полоса: земля от level−BAND_RANGE до level+BAND_RANGE.
const BAND_RANGE: float = 1.0
## Прижим бикубики к интерполяции коллизии, м: Catmull-Rom на крутых
## склонах отклоняется сильнее — отклонение зажимается (≤ LIMIT от
## треугольной высоты), полоса держится в 5 см от коллизии (SPEC 9.1).
const TENSION_LIMIT: float = 0.03
## Подъём полосы над чанками, м: чуть выше поверхности (чанк ниже),
## но ниже кольца П14 (0.004) — кольцо скользит по полосе без
## копланарного мерцания.
const BAND_LIFT: float = 0.001
## Гашение бикубики к краю полосы, клеток (1 м): край ровно над чанком.
const BAND_EDGE_CELLS: float = 3.0
## Труба к высоте коллизии, м (П15 9.1): физика (Jolt) режет квад карты
## диагональю (x+1,z)–(x,z+1) — противоположно печёным чанкам, и на
## перекошенных клетках (|h00+h11−h10−h01| > 0.1, ~30% клеток полосы)
## чанковая высота расходится с коллизией на метры. Полоса зажимается
## в ±COLLISION_CLAMP вокруг высоты коллизии: отклонение ≤5 см (тест
## SPEC), у края полосы ступенька к чанку не больше этой же величины.
## На пологих клетках труба шире естественного расхождения — неактивна.
const COLLISION_CLAMP: float = 0.045

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

## Кэш меша береговой полосы (П15 9.1; дефолтный уровень и шаг).
static var _band_mesh_cache: ArrayMesh = null


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


## Треугольная высота чанков в точке (fx, fz): диагональ квадрата
## (x,z)–(x+1,z+1) — та же триангуляция, что у печёных чанков
## (TerrainBuilder) и ветки detail_ring шейдера земли.
static func tri_height(
	heights: PackedFloat32Array, fx: float, fz: float,
) -> float:
	var x0: int = clampi(int(floorf(fx)), -IslandGen.HALF, IslandGen.HALF - 1)
	var z0: int = clampi(int(floorf(fz)), -IslandGen.HALF, IslandGen.HALF - 1)
	var h00: float = heights[_node(x0, z0)]
	var h10: float = heights[_node(x0 + 1, z0)]
	var h01: float = heights[_node(x0, z0 + 1)]
	var h11: float = heights[_node(x0 + 1, z0 + 1)]
	var u: float = clampf(fx - float(x0), 0.0, 1.0)
	var v: float = clampf(fz - float(z0), 0.0, 1.0)
	if u >= v:
		return h00 + (h10 - h00) * u + (h11 - h10) * v
	return h00 + (h01 - h00) * v + (h11 - h01) * u


## Высота коллизии HeightMapShape3D в точке (fx, fz): физика режет квад
## диагональю (x+1,z)–(x,z+1) — на рёбрах совпадает с tri_height, внутри
## расходится на |h00+h11−h10−h01|/2 (проверено raycast-пробником на
## седловой клетке). Полоса прижимается к этой высоте (COLLISION_CLAMP),
## чтобы у кромки воды виденная земля совпадала с той, на которой стоят.
static func collision_height(
	heights: PackedFloat32Array, fx: float, fz: float,
) -> float:
	var x0: int = clampi(int(floorf(fx)), -IslandGen.HALF, IslandGen.HALF - 1)
	var z0: int = clampi(int(floorf(fz)), -IslandGen.HALF, IslandGen.HALF - 1)
	var h00: float = heights[_node(x0, z0)]
	var h10: float = heights[_node(x0 + 1, z0)]
	var h01: float = heights[_node(x0, z0 + 1)]
	var h11: float = heights[_node(x0 + 1, z0 + 1)]
	var u: float = clampf(fx - float(x0), 0.0, 1.0)
	var v: float = clampf(fz - float(z0), 0.0, 1.0)
	if u + v <= 1.0:
		return h00 + (h10 - h00) * u + (h01 - h00) * v
	return h10 * (1.0 - v) + h01 * (1.0 - u) + h11 * (u + v - 1.0)


## Бикубическая высота (Catmull-Rom 4×4 узла) с прижимом к треугольной
## высоте коллизии: отклонение ≤ TENSION_LIMIT (полоса ≤5 см от
## коллизии, SPEC П15 9.1). Формула та же, что в ветке detail_ring
## шейдера forest_ground (без шва на стыке кольца и полосы).
static func cubic_height(
	heights: PackedFloat32Array, fx: float, fz: float,
) -> float:
	var x1: int = clampi(int(floorf(fx)), -IslandGen.HALF + 1,
		IslandGen.HALF - 2)
	var z1: int = clampi(int(floorf(fz)), -IslandGen.HALF + 1,
		IslandGen.HALF - 2)
	var tx: float = clampf(fx - float(x1), 0.0, 1.0)
	var tz: float = clampf(fz - float(z1), 0.0, 1.0)
	var col := [0.0, 0.0, 0.0, 0.0]
	for k: int in 4:
		var zz: int = z1 - 1 + k
		col[k] = _catmull(
			heights[_node(x1 - 1, zz)], heights[_node(x1, zz)],
			heights[_node(x1 + 1, zz)], heights[_node(x1 + 2, zz)], tx)
	var cubic: float = _catmull(col[0], col[1], col[2], col[3], tz)
	var linear: float = tri_height(heights, fx, fz)
	var gap: float = absf(cubic - linear)
	var k_pin: float = clampf(gap / TENSION_LIMIT, 0.0, 1.0)
	return lerpf(cubic, linear, k_pin)


## Узловая интерполяция Catmull-Rom (1, 0.5·(...)).
static func _catmull(
	p0: float, p1: float, p2: float, p3: float, t: float,
) -> float:
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t)


## Индекс узла карты высот.
static func _node(x: int, z: int) -> int:
	return (z + IslandGen.HALF) * IslandGen.POINTS + x + IslandGen.HALF


## Маска клеток полосы берега (П15 9.1): квад земли, чьи углы пересекают
## диапазон высот level ± BAND_RANGE. faces × faces (квад 1 м).
static func band_mask(art: IslandArt, level: float) -> PackedByteArray:
	var heights: PackedFloat32Array = art.heights
	var faces: int = IslandGen.POINTS - 1
	var mask := PackedByteArray()
	mask.resize(faces * faces)
	for fz: int in faces:
		for fx: int in faces:
			var h00: float = heights[_node(fx - IslandGen.HALF,
				fz - IslandGen.HALF)]
			var h10: float = heights[_node(fx - IslandGen.HALF + 1,
				fz - IslandGen.HALF)]
			var h01: float = heights[_node(fx - IslandGen.HALF,
				fz - IslandGen.HALF + 1)]
			var h11: float = heights[_node(fx - IslandGen.HALF + 1,
				fz - IslandGen.HALF + 1)]
			var low: float = minf(minf(h00, h10), minf(h01, h11))
			var high: float = maxf(maxf(h00, h10), maxf(h01, h11))
			if low <= level + BAND_RANGE and high >= level - BAND_RANGE:
				mask[fz * faces + fx] = 1
	return mask


## Слой клетки от края полосы (0 — крайняя, у которой есть сосед вне
## полосы): гашение бикубики и подъёма к краю.
static func band_layers(mask: PackedByteArray) -> PackedByteArray:
	var faces: int = IslandGen.POINTS - 1
	var layers := PackedByteArray()
	layers.resize(faces * faces)
	layers.fill(255)
	var frontier: Array[int] = []
	for fz: int in faces:
		for fx: int in faces:
			var i: int = fz * faces + fx
			if mask[i] == 0:
				continue
			var edge: bool = fx == 0 or fx == faces - 1 \
				or fz == 0 or fz == faces - 1
			for d: int in 4:
				var nx: int = fx + DX8[d]
				var nz: int = fz + DZ8[d]
				if nx < 0 or nx >= faces or nz < 0 or nz >= faces \
					or mask[nz * faces + nx] == 0:
					edge = true
			if edge:
				layers[i] = 0
				frontier.append(i)
	while not frontier.is_empty():
		var next_frontier: Array[int] = []
		for i: int in frontier:
			var fx: int = i % faces
			var fz: int = i / faces
			for d: int in 4:
				var nx: int = fx + DX8[d]
				var nz: int = fz + DZ8[d]
				if nx < 0 or nx >= faces or nz < 0 or nz >= faces:
					continue
				var j: int = nz * faces + nx
				if mask[j] == 1 and layers[j] > layers[i] + 1:
					layers[j] = layers[i] + 1
					if layers[j] < 255:
						next_frontier.append(j)
		frontier = next_frontier
	return layers


## Меш береговой полосы (П15 9.1): визуальная сетка вдоль всей береговой
## линии с шагом BAND_STEP, высоты — бикубика с прижимом; к краю полосы
## высота прижимается к чанкам (стык без шва), в глубине — BAND_LIFT;
## затем вся высота зажимается в трубу ±COLLISION_CLAMP вокруг высоты
## коллизии (отклонение ≤5 см, SPEC П15 9.1). Только визуал: коллизия
## и генератор не меняются.
static func build_band_mesh(
	art: IslandArt, level: float, step: float = BAND_STEP,
) -> ArrayMesh:
	# Кэш дефолтной полосы (остров и уровень воды одни на процесс; в
	# тестах IslandView строится по несколько раз — без кэша каждый вход
	# платит ~1.3 с сборки). Нестандартный step — мимо кэша (пробы).
	if step == BAND_STEP and level == IslandGen.SEA_LEVEL \
			and _band_mesh_cache != null:
		return _band_mesh_cache
	var heights: PackedFloat32Array = art.heights
	var faces: int = IslandGen.POINTS - 1
	var mask := band_mask(art, level)
	var layers := band_layers(mask)
	var sub: int = int(round(1.0 / step))
	var grid_side: int = faces * sub + 1
	# Дедуп вершин глобальной решётки step (общие рёбра клеток) — прямой
	# массив индексов вместо словаря: сборка всей полосы < 0.5 с.
	var grid := PackedInt32Array()
	grid.resize(grid_side * grid_side)
	grid.fill(-1)
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	var cell_side: int = sub + 1
	var cell_cubic := PackedFloat32Array()
	cell_cubic.resize(cell_side * cell_side)

	for fz: int in faces:
		for fx: int in faces:
			if mask[fz * faces + fx] == 0:
				continue
			var blend: float = clampf(
				float(layers[fz * faces + fx]) / BAND_EDGE_CELLS, 0.0, 1.0)
			# Соседние клетки полосы могут быть ближе к краю — вершины
			# стыка берут минимум гашения (шов между слоями плавный).
			var blend_x: float = blend
			if fx + 1 < faces and mask[fz * faces + fx + 1] == 1:
				blend_x = minf(blend, clampf(
					float(layers[fz * faces + fx + 1])
					/ BAND_EDGE_CELLS, 0.0, 1.0))
			var blend_z: float = blend
			if fz + 1 < faces and mask[(fz + 1) * faces + fx] == 1:
				blend_z = minf(blend, clampf(
					float(layers[(fz + 1) * faces + fx])
					/ BAND_EDGE_CELLS, 0.0, 1.0))
			var blend_diag: float = minf(blend_x, blend_z)
			# Сырая бикубика подквадов клетки — один расчёт на клетку
			# (колонки Catmull-X по строкам узлов), прижим к чанковой
			# высоте — по вершине в _band_vertex.
			_cell_cubic(heights, fx, fz, sub, cell_cubic)
			for sz: int in sub:
				for sx: int in sub:
					var qx0: float = float(fx - IslandGen.HALF) \
						+ float(sx) / float(sub)
					var qz0: float = float(fz - IslandGen.HALF) \
						+ float(sz) / float(sub)
					var a: int = _band_vertex(grid, grid_side, verts,
						heights, fx * sub + sx, fz * sub + sz,
						qx0, qz0, blend, cell_cubic[sz * cell_side + sx])
					var b: int = _band_vertex(grid, grid_side, verts,
						heights, fx * sub + sx + 1, fz * sub + sz,
						qx0 + step, qz0, blend_x,
						cell_cubic[sz * cell_side + sx + 1])
					var c: int = _band_vertex(grid, grid_side, verts,
						heights, fx * sub + sx, fz * sub + sz + 1,
						qx0, qz0 + step, blend_z,
						cell_cubic[(sz + 1) * cell_side + sx])
					var d: int = _band_vertex(grid, grid_side, verts,
						heights, fx * sub + sx + 1, fz * sub + sz + 1,
						qx0 + step, qz0 + step, blend_diag,
						cell_cubic[(sz + 1) * cell_side + sx + 1])
					# Та же диагональ и намотка, что у чанков.
					indices.append(a)
					indices.append(d)
					indices.append(c)
					indices.append(a)
					indices.append(b)
					indices.append(d)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if step == BAND_STEP and level == IslandGen.SEA_LEVEL:
		_band_mesh_cache = mesh
	return mesh


## Сырая бикубическая высота (Catmull-Rom, без прижима) подквадов клетки
## (fx, fz) в решётку (sub+1)² — колонки по строкам узлов считаются один
## раз на клетку (на целых узлах совпадает с соседями — швов нет; на
## краю карты аргументы клампятся, как в cubic_height). Формула та же,
## что в ветке detail_ring шейдера forest_ground (стык кольца и полосы).
static func _cell_cubic(
	heights: PackedFloat32Array, fx: int, fz: int,
	sub: int, out: PackedFloat32Array,
) -> void:
	var gx: int = fx - IslandGen.HALF
	var gz: int = fz - IslandGen.HALF
	var x1: int = clampi(gx, -IslandGen.HALF + 1, IslandGen.HALF - 2)
	var z1: int = clampi(gz, -IslandGen.HALF + 1, IslandGen.HALF - 2)
	var tx0: float = float(gx - x1)
	var tz0: float = float(gz - z1)
	var side: int = sub + 1
	var col0 := PackedFloat32Array()
	var col1 := PackedFloat32Array()
	var col2 := PackedFloat32Array()
	var col3 := PackedFloat32Array()
	col0.resize(side)
	col1.resize(side)
	col2.resize(side)
	col3.resize(side)
	var cols: Array[PackedFloat32Array] = [col0, col1, col2, col3]
	for k: int in 4:
		# Узлы строки z1-1+k: подряд в heights — от x1-1 до x1+2.
		var row: int = _node(x1 - 1, z1 - 1 + k)
		var c: PackedFloat32Array = cols[k]
		for sx: int in side:
			var t: float = tx0 + float(sx) / float(sub)
			c[sx] = _catmull(
				heights[row], heights[row + 1],
				heights[row + 2], heights[row + 3], t)
	for sz: int in side:
		var tz: float = tz0 + float(sz) / float(sub)
		var out_row: int = sz * side
		for sx: int in side:
			out[out_row + sx] = _catmull(
				col0[sx], col1[sx], col2[sx], col3[sx], tz)


## Вершина полосы по узлу решётки (создаётся один раз); высота:
## треугольная чанковая + BAND_LIFT, бикубика добавляется гашением
## blend (0 на краю — совпадение с чанком, 1 в глубине полосы), но
## никогда не опускается ниже чанка (утопленная полоса рвёт шов);
## результат зажимается в трубу ±COLLISION_CLAMP вокруг высоты
## коллизии — на пологих клетках труба неактивна, на перекошенных
## полоса остаётся у ног игрока (≤5 см от коллизии).
static func _band_vertex(
	grid: PackedInt32Array, grid_side: int, verts: PackedVector3Array,
	heights: PackedFloat32Array, ix: int, iz: int,
	wx: float, wz: float, blend: float, cubic_raw: float,
) -> int:
	var key: int = iz * grid_side + ix
	if grid[key] >= 0:
		return grid[key]
	var tri: float = tri_height(heights, wx, wz)
	var cubic: float = lerpf(cubic_raw, tri,
		clampf(absf(cubic_raw - tri) / TENSION_LIMIT, 0.0, 1.0))
	var h: float = tri + BAND_LIFT \
		+ maxf(cubic - tri - BAND_LIFT, 0.0) * blend
	var col: float = collision_height(heights, wx, wz)
	h = clampf(h, col - COLLISION_CLAMP, col + COLLISION_CLAMP)
	verts.append(Vector3(wx, h, wz))
	grid[key] = verts.size() - 1
	return verts.size() - 1



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
